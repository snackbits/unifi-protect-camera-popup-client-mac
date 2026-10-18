// Package tunnel runs a userspace WireGuard peer (wireguard-go + gVisor netstack)
// that is visible only to this process, and exposes local TCP/UDP port forwards
// on 127.0.0.1 so other programs (libVLC, ffmpeg, curl) can reach hosts behind it.
package tunnel

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
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

type Tunnel struct {
	Config *wgconf.Config
	Net    *netstack.Net
	dev    *device.Device

	mu       sync.Mutex
	forwards []io.Closer
	closed   bool

	FwdConns   atomic.Int64
	FwdBytesUp atomic.Int64 // local -> remote
	FwdBytesDn atomic.Int64 // remote -> local
}

func resolve(host string) (netip.Addr, error) {
	ips, err := net.DefaultResolver.LookupNetIP(context.Background(), "ip", host)
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
	var local []netip.Addr
	for _, p := range cfg.Interface.Addresses {
		local = append(local, p.Addr())
	}
	tdev, tnet, err := netstack.CreateNetTUN(local, cfg.Interface.DNS, cfg.MTUOrDefault())
	if err != nil {
		return nil, fmt.Errorf("netstack: %w", err)
	}
	dev := device.NewDevice(tdev, conn.NewDefaultBind(), device.NewLogger(logLevel, "wg: "))
	uapi, err := cfg.UAPI(resolve)
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
	return &Tunnel{Config: cfg, Net: tnet, dev: dev}, nil
}

func (t *Tunnel) Close() {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return
	}
	t.closed = true
	fw := t.forwards
	t.forwards = nil
	t.mu.Unlock()
	for _, c := range fw {
		c.Close()
	}
	t.dev.Close()
}

// DialContext dials through the tunnel (for http.Transport etc.).
func (t *Tunnel) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	return t.Net.DialContext(ctx, network, addr)
}

// HTTPClient returns a client whose connections go through the tunnel.
// insecure skips TLS verification (UniFi consoles use self-signed certs);
// a real app should pin the console certificate instead.
func (t *Tunnel) HTTPClient(insecure bool) *http.Client {
	tr := &http.Transport{
		DialContext:         t.DialContext,
		TLSClientConfig:     &tls.Config{InsecureSkipVerify: insecure},
		ForceAttemptHTTP2:   true,
		TLSHandshakeTimeout: 10 * time.Second,
	}
	return &http.Client{Transport: tr, Timeout: 30 * time.Second}
}

func (t *Tunnel) track(c io.Closer) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return false
	}
	t.forwards = append(t.forwards, c)
	return true
}

// AddForward listens on 127.0.0.1:localPort (0 = ephemeral) with a normal macOS
// socket and relays every accepted connection to remoteHost:remotePort via the tunnel.
// Returns the bound local port.
func (t *Tunnel) AddForward(localPort int, remoteHost string, remotePort int) (int, error) {
	ln, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(localPort)))
	if err != nil {
		return 0, err
	}
	if !t.track(ln) {
		ln.Close()
		return 0, errors.New("Tunnel geschlossen")
	}
	remote := net.JoinHostPort(remoteHost, strconv.Itoa(remotePort))
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go t.relayTCP(c, remote)
		}
	}()
	return ln.Addr().(*net.TCPAddr).Port, nil
}

func (t *Tunnel) relayTCP(local net.Conn, remote string) {
	defer local.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	r, err := t.Net.DialContext(ctx, "tcp", remote)
	cancel()
	if err != nil {
		log.Printf("forward %s: %v", remote, err)
		return
	}
	defer r.Close()
	t.FwdConns.Add(1)
	done := make(chan struct{}, 2)
	go func() {
		n, _ := io.Copy(r, local)
		t.FwdBytesUp.Add(n)
		if cw, ok := r.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	go func() {
		n, _ := io.Copy(local, r)
		t.FwdBytesDn.Add(n)
		if cw, ok := local.(*net.TCPConn); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	<-done
	<-done
}

// AddUDPForward listens on 127.0.0.1:localPort (UDP). Datagrams from the most
// recent local sender are relayed to remoteHost:remotePort through the tunnel;
// replies go back to that sender. Enough for talkback (one sender).
func (t *Tunnel) AddUDPForward(localPort int, remoteHost string, remotePort int) (int, error) {
	raddr, err := netip.ParseAddrPort(net.JoinHostPort(remoteHost, strconv.Itoa(remotePort)))
	if err != nil {
		return 0, fmt.Errorf("UDP-Ziel muss IP sein: %w", err)
	}
	lc, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: localPort})
	if err != nil {
		return 0, err
	}
	rc, err := t.Net.DialUDPAddrPort(netip.AddrPort{}, raddr)
	if err != nil {
		lc.Close()
		return 0, err
	}
	if !t.track(lc) || !t.track(rc) {
		lc.Close()
		rc.Close()
		return 0, errors.New("Tunnel geschlossen")
	}
	var peer atomic.Pointer[net.UDPAddr]
	go func() {
		buf := make([]byte, 65535)
		for {
			n, from, err := lc.ReadFromUDP(buf)
			if err != nil {
				return
			}
			peer.Store(from)
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
			if p := peer.Load(); p != nil {
				lc.WriteToUDP(buf[:n], p)
			}
		}
	}()
	return lc.LocalAddr().(*net.UDPAddr).Port, nil
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
}

func (t *Tunnel) Status() (Status, error) {
	s := Status{Up: true, FwdConns: t.FwdConns.Load(), FwdBytesUp: t.FwdBytesUp.Load(), FwdBytesDown: t.FwdBytesDn.Load()}
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
