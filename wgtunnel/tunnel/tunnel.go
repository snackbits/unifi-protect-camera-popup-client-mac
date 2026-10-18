// Package tunnel runs a userspace WireGuard peer (wireguard-go + gVisor netstack)
// that is visible only to this process, and exposes local TCP/UDP port forwards
// on 127.0.0.1 so other code (URLSession, libVLC) can reach hosts behind it.
//
// Forwards are deliberately narrow: they bind 127.0.0.1 only, reach only
// addresses inside the peers' AllowedIPs, a UDP forward answers only one local
// sender at a time, and every listener closes with the tunnel.
package tunnel

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"

	"wgtunnel/wgconf"
)

// DefaultKeepalive is used for peers whose config has no PersistentKeepalive.
// The app sits behind NAT on foreign networks; without keepalives the mapping
// expires and an idle tunnel only notices that on the next request.
const DefaultKeepalive = 25

// UDPRelockIdle is how long the local sender a UDP forward is locked to must
// stay silent before another local sender may take the forward over. Each
// talkback session opens a new socket (new source port); the old one is quiet
// by then.
const UDPRelockIdle = 3 * time.Second

type Tunnel struct {
	Config *wgconf.Config
	Net    *netstack.Net
	dev    *device.Device

	mu        sync.Mutex
	listeners []io.Closer
	byRemote  map[string]int      // "tcp/host:port" or "udp/ip:port" -> local port
	active    map[*relay]struct{} // relayed TCP connections currently open
	udpLocks  map[int]*udpLock    // local port -> sender lock of that UDP forward
	closed    bool

	// Replaceable in tests: clock for UDP sender locks, DNS through the tunnel.
	now        func() time.Time
	lookupHost func(ctx context.Context, host string) ([]string, error)

	FwdConns   atomic.Int64
	FwdBytesUp atomic.Int64 // local -> remote
	FwdBytesDn atomic.Int64 // remote -> local
	// UDPForeignDropped counts datagrams a UDP forward discarded because they
	// came from a local address other than the active one it is locked to.
	UDPForeignDropped atomic.Int64
}

// relay is one accepted local connection and its tunnel-side counterpart.
type relay struct {
	local, remote net.Conn
}

func (r *relay) close() {
	r.local.Close()
	r.remote.Close()
}

// udpLock is the local sender a UDP forward serves. The first sender takes
// the lock; another sender gets it only after the locked one has sent nothing
// for idle, or after clear (ResetConnections, ReleaseUDPForward).
type udpLock struct {
	idle time.Duration
	now  func() time.Time

	mu   sync.Mutex
	peer netip.AddrPort // invalid = unlocked
	last time.Time      // last datagram from peer
}

// admit reports whether a datagram from 'from' may pass, (re)locking to it
// when the forward is unlocked or the locked sender has gone idle.
func (l *udpLock) admit(from netip.AddrPort) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if l.peer.IsValid() && l.peer != from && now.Sub(l.last) < l.idle {
		return false
	}
	l.peer, l.last = from, now
	return true
}

// current is where replies go; invalid while unlocked.
func (l *udpLock) current() netip.AddrPort {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.peer
}

func (l *udpLock) clear() {
	l.mu.Lock()
	l.peer = netip.AddrPort{}
	l.mu.Unlock()
}

// ResolveTimeout bounds one endpoint lookup (Start, Rebind): a stuck resolver
// must not keep the bridge queue busy for good.
const ResolveTimeout = 10 * time.Second

// Resolver maps an endpoint host name to an IP (outside the tunnel).
var Resolver = func(host string) (netip.Addr, error) {
	ctx, cancel := context.WithTimeout(context.Background(), ResolveTimeout)
	defer cancel()
	ips, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
	if err != nil {
		return netip.Addr{}, err
	}
	for _, ip := range ips { // prefer IPv4
		if ip.Unmap().Is4() {
			return ip.Unmap(), nil
		}
	}
	if len(ips) == 0 {
		return netip.Addr{}, errors.New("keine Adresse")
	}
	return ips[0], nil
}

// Start parses a wg-quick config and brings the userspace device up.
// logLevel: device.LogLevelSilent / Error / Verbose.
func Start(configText string, logLevel int) (*Tunnel, error) {
	cfg, err := wgconf.Parse(configText)
	if err != nil {
		return nil, err
	}
	return StartConfig(cfg, logLevel)
}

func StartConfig(cfg *wgconf.Config, logLevel int) (*Tunnel, error) {
	for i := range cfg.Peers {
		if cfg.Peers[i].PersistentKeepalive == 0 {
			cfg.Peers[i].PersistentKeepalive = DefaultKeepalive
		}
	}
	var local []netip.Addr
	for _, p := range cfg.Interface.Addresses {
		local = append(local, p.Addr())
	}
	tdev, tnet, err := netstack.CreateNetTUN(local, cfg.Interface.DNS, cfg.MTUOrDefault())
	if err != nil {
		return nil, fmt.Errorf("netstack: %w", err)
	}
	dev := device.NewDevice(tdev, conn.NewDefaultBind(), device.NewLogger(logLevel, "wg: "))
	uapi, err := cfg.UAPI(Resolver)
	if err != nil {
		dev.Close()
		return nil, err
	}
	if err := dev.IpcSet(uapi); err != nil {
		dev.Close()
		return nil, fmt.Errorf("IpcSet: %w", err)
	}
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, fmt.Errorf("Up: %w", err)
	}
	return &Tunnel{
		Config: cfg, Net: tnet, dev: dev,
		byRemote: map[string]int{}, active: map[*relay]struct{}{}, udpLocks: map[int]*udpLock{},
		now: time.Now, lookupHost: tnet.LookupContextHost,
	}, nil
}

func (t *Tunnel) Close() {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return
	}
	t.closed = true
	ls := t.listeners
	t.listeners = nil
	rs := t.active
	t.active = map[*relay]struct{}{}
	t.mu.Unlock()
	for _, c := range ls {
		c.Close()
	}
	for r := range rs {
		r.close()
	}
	t.dev.Close()
}

// DialContext dials through the tunnel.
func (t *Tunnel) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	return t.Net.DialContext(ctx, network, addr)
}

// allowed reports whether ip lies inside the AllowedIPs of any peer, i.e.
// whether WireGuard would route it through the tunnel at all.
func (t *Tunnel) allowed(ip netip.Addr) bool {
	ip = ip.Unmap()
	for _, p := range t.Config.Peers {
		for _, pfx := range p.AllowedIPs {
			if pfx.Contains(ip) {
				return true
			}
		}
	}
	return false
}

// target turns a forward destination into an address inside AllowedIPs.
// Host names are resolved once, through the tunnel's DNS, and the forward
// stays pinned to the first allowed answer.
func (t *Tunnel) target(host string) (netip.Addr, error) {
	if ip, err := netip.ParseAddr(host); err == nil {
		if !t.allowed(ip) {
			return netip.Addr{}, fmt.Errorf("Ziel %s liegt nicht in AllowedIPs", ip)
		}
		return ip.Unmap(), nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	names, err := t.lookupHost(ctx, host)
	if err != nil {
		return netip.Addr{}, fmt.Errorf("Ziel %q nicht auflösbar: %v", host, err)
	}
	for _, n := range names {
		if ip, err := netip.ParseAddr(n); err == nil && t.allowed(ip) {
			return ip.Unmap(), nil
		}
	}
	return netip.Addr{}, fmt.Errorf("Ziel %q liegt nicht in AllowedIPs", host)
}

// lookup returns the existing local port for key, or registers the listeners
// produced by open. Holding mu across open keeps two callers from binding twice.
func (t *Tunnel) lookup(key string, open func() (int, []io.Closer, error)) (int, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return 0, errors.New("Tunnel geschlossen")
	}
	if p, ok := t.byRemote[key]; ok {
		return p, nil
	}
	p, cs, err := open()
	if err != nil {
		return 0, err
	}
	t.byRemote[key] = p
	t.listeners = append(t.listeners, cs...)
	return p, nil
}

// AddForward listens on 127.0.0.1:localPort (0 = ephemeral) with a normal macOS
// socket and relays every accepted connection to remoteHost:remotePort via the tunnel.
// Asking again for the same remote returns the port bound the first time.
// remoteHost must be (or resolve to) an address inside AllowedIPs.
func (t *Tunnel) AddForward(localPort int, remoteHost string, remotePort int) (int, error) {
	if remotePort < 1 || remotePort > 65535 {
		return 0, fmt.Errorf("ungültiger Zielport %d", remotePort)
	}
	host := remoteHost
	if ip, err := netip.ParseAddr(remoteHost); err == nil {
		host = ip.Unmap().String() // ::ffff:a.b.c.d and a.b.c.d share one forward
	}
	key := "tcp/" + net.JoinHostPort(host, strconv.Itoa(remotePort))
	// Known remote: answer from the cache without resolving again.
	t.mu.Lock()
	p, known := t.byRemote[key]
	closed := t.closed
	t.mu.Unlock()
	if closed {
		return 0, errors.New("Tunnel geschlossen")
	}
	if known {
		return p, nil
	}
	// Resolve outside mu: a DNS lookup must not block Close or ResetConnections.
	ip, err := t.target(remoteHost)
	if err != nil {
		return 0, err
	}
	remote := netip.AddrPortFrom(ip, uint16(remotePort)).String()
	return t.lookup(key, func() (int, []io.Closer, error) {
		ln, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(localPort)))
		if err != nil {
			return 0, nil, err
		}
		go func() {
			for {
				c, err := ln.Accept()
				if err != nil {
					return
				}
				go t.relayTCP(c, remote)
			}
		}()
		return ln.Addr().(*net.TCPAddr).Port, []io.Closer{ln}, nil
	})
}

func (t *Tunnel) track(r *relay) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return false
	}
	t.active[r] = struct{}{}
	return true
}

func (t *Tunnel) untrack(r *relay) {
	t.mu.Lock()
	delete(t.active, r)
	t.mu.Unlock()
}

func (t *Tunnel) relayTCP(local net.Conn, remote string) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	rc, err := t.Net.DialContext(ctx, "tcp", remote)
	cancel()
	if err != nil {
		log.Printf("forward %s: %v", remote, err)
		local.Close()
		return
	}
	r := &relay{local: local, remote: rc}
	if !t.track(r) {
		r.close()
		return
	}
	defer t.untrack(r)
	defer r.close()
	t.FwdConns.Add(1)
	done := make(chan struct{}, 2)
	go func() {
		n, _ := io.Copy(rc, local)
		t.FwdBytesUp.Add(n)
		if cw, ok := rc.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	go func() {
		n, _ := io.Copy(local, rc)
		t.FwdBytesDn.Add(n)
		if cw, ok := local.(*net.TCPConn); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	<-done
	<-done
}

// ResetConnections closes every relayed TCP connection but keeps the listeners,
// so clients reconnect to the same 127.0.0.1 ports. Needed after an outage:
// a gVisor TCP connection that lived through a long blackout can stay stuck
// forever although the tunnel itself works again. It also unlocks every UDP
// forward, so the next local sender takes it over at once. Returns how many
// TCP connections were closed.
func (t *Tunnel) ResetConnections() int {
	t.mu.Lock()
	rs := t.active
	t.active = map[*relay]struct{}{}
	locks := make([]*udpLock, 0, len(t.udpLocks))
	for _, l := range t.udpLocks {
		locks = append(locks, l)
	}
	t.mu.Unlock()
	for r := range rs {
		r.close()
	}
	for _, l := range locks {
		l.clear()
	}
	return len(rs)
}

// ReleaseUDPForward unlocks the UDP forward on 127.0.0.1:localPort, so the
// next local sender takes it over at once instead of after UDPRelockIdle.
// Call it right before a new talkback session starts on that forward; the
// lock then holds again for the whole session.
func (t *Tunnel) ReleaseUDPForward(localPort int) error {
	t.mu.Lock()
	lock, ok := t.udpLocks[localPort]
	closed := t.closed
	t.mu.Unlock()
	if closed {
		return errors.New("Tunnel geschlossen")
	}
	if !ok {
		return fmt.Errorf("keine UDP-Weiterleitung auf Port %d", localPort)
	}
	lock.clear()
	return nil
}

// Rebind re-resolves endpoint host names and rebinds the UDP socket. Call after
// the Mac changed networks (new Wi-Fi, wake from sleep, hotspot).
func (t *Tunnel) Rebind() error {
	var b strings.Builder
	for _, p := range t.Config.Peers {
		addr, err := netip.ParseAddr(p.EndpointHost)
		if err != nil {
			addr, err = Resolver(p.EndpointHost)
			if err != nil {
				return fmt.Errorf("Endpoint %q nicht auflösbar: %v", p.EndpointHost, err)
			}
		}
		fmt.Fprintf(&b, "public_key=%s\nupdate_only=true\nendpoint=%s\n",
			p.PublicKey.Hex(), netip.AddrPortFrom(addr.Unmap(), p.EndpointPort))
	}
	if err := t.dev.IpcSet(b.String()); err != nil {
		return fmt.Errorf("IpcSet: %w", err)
	}
	return t.dev.BindUpdate()
}

// AddUDPForward listens on 127.0.0.1:localPort (UDP) and relays datagrams to
// remoteHost:remotePort (an IP inside AllowedIPs) through the tunnel. The
// forward serves one local sender at a time: the first one locks it, replies
// go only to it, and datagrams from other local addresses are dropped (counted
// in UDPForeignDropped) until the locked sender has been silent for
// UDPRelockIdle, or ResetConnections or ReleaseUDPForward ran. Enough for talkback (one sender per
// session, a new source port each session).
func (t *Tunnel) AddUDPForward(localPort int, remoteHost string, remotePort int) (int, error) {
	raddr, err := netip.ParseAddrPort(net.JoinHostPort(remoteHost, strconv.Itoa(remotePort)))
	if err != nil {
		return 0, fmt.Errorf("UDP-Ziel muss IP sein: %w", err)
	}
	raddr = netip.AddrPortFrom(raddr.Addr().Unmap(), raddr.Port())
	if !t.allowed(raddr.Addr()) {
		return 0, fmt.Errorf("Ziel %s liegt nicht in AllowedIPs", raddr.Addr())
	}
	return t.lookup("udp/"+raddr.String(), func() (int, []io.Closer, error) {
		lc, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: localPort})
		if err != nil {
			return 0, nil, err
		}
		rc, err := t.Net.DialUDPAddrPort(netip.AddrPort{}, raddr)
		if err != nil {
			lc.Close()
			return 0, nil, err
		}
		localPort := lc.LocalAddr().(*net.UDPAddr).Port
		lock := &udpLock{idle: UDPRelockIdle, now: t.now}
		t.udpLocks[localPort] = lock // lookup holds mu while open runs
		go func() {
			buf := make([]byte, 65535)
			for {
				n, from, err := lc.ReadFromUDPAddrPort(buf)
				if err != nil {
					return
				}
				if !lock.admit(from) {
					if d := t.UDPForeignDropped.Add(1); d == 1 || d%1000 == 0 {
						log.Printf("UDP-Weiterleitung 127.0.0.1:%d: bisher %d Datagramme fremder lokaler Absender verworfen", localPort, d)
					}
					continue
				}
				rc.Write(buf[:n])
			}
		}()
		go func() {
			buf := make([]byte, 65535)
			for {
				n, err := rc.Read(buf)
				if err != nil {
					return
				}
				if p := lock.current(); p.IsValid() {
					lc.WriteToUDPAddrPort(buf[:n], p)
				}
			}
		}()
		return localPort, []io.Closer{lc, rc}, nil
	})
}

type PeerStatus struct {
	PublicKey     string `json:"publicKey"`
	Endpoint      string `json:"endpoint"`
	LastHandshake int64  `json:"lastHandshakeUnix"`
	HandshakeAgeS int64  `json:"handshakeAgeSeconds"` // -1 = never
	RxBytes       int64  `json:"rxBytes"`
	TxBytes       int64  `json:"txBytes"`
	KeepaliveSecs int    `json:"keepaliveSeconds"`
}

type Status struct {
	Up           bool         `json:"up"`
	Peers        []PeerStatus `json:"peers"`
	FwdConns     int64        `json:"forwardConnections"`
	FwdBytesUp   int64        `json:"forwardBytesUp"`
	FwdBytesDown int64        `json:"forwardBytesDown"`
	UDPDropped   int64        `json:"udpForeignDropped"`
}

func (t *Tunnel) Status() (Status, error) {
	s := Status{Up: true, Peers: []PeerStatus{}, FwdConns: t.FwdConns.Load(), FwdBytesUp: t.FwdBytesUp.Load(), FwdBytesDown: t.FwdBytesDn.Load(), UDPDropped: t.UDPForeignDropped.Load()}
	raw, err := t.dev.IpcGet()
	if err != nil {
		return s, err
	}
	var cur *PeerStatus
	var sec, nsec int64
	flush := func() {
		if cur != nil {
			cur.LastHandshake = sec
			cur.HandshakeAgeS = -1
			if sec > 0 {
				cur.HandshakeAgeS = int64(time.Since(time.Unix(sec, nsec)).Seconds())
			}
			s.Peers = append(s.Peers, *cur)
		}
	}
	for _, line := range strings.Split(raw, "\n") {
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		switch k {
		case "public_key":
			flush()
			cur, sec, nsec = &PeerStatus{PublicKey: v}, 0, 0
		case "endpoint":
			cur.Endpoint = v
		case "last_handshake_time_sec":
			sec, _ = strconv.ParseInt(v, 10, 64)
		case "last_handshake_time_nsec":
			nsec, _ = strconv.ParseInt(v, 10, 64)
		case "rx_bytes":
			cur.RxBytes, _ = strconv.ParseInt(v, 10, 64)
		case "tx_bytes":
			cur.TxBytes, _ = strconv.ParseInt(v, 10, 64)
		case "persistent_keepalive_interval":
			cur.KeepaliveSecs, _ = strconv.Atoi(v)
		}
	}
	flush()
	return s, nil
}
