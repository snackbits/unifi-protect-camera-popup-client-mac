package tunnel

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/curve25519"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

var consoleIP = netip.MustParseAddr("192.168.1.1")

func keypair(t *testing.T) (priv, pub [32]byte) {
	t.Helper()
	if _, err := rand.Read(priv[:]); err != nil {
		t.Fatal(err)
	}
	priv[0] &= 248
	priv[31] = (priv[31] & 127) | 64
	p, err := curve25519.X25519(priv[:], curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	copy(pub[:], p)
	return
}

func b64(k [32]byte) string { return base64.StdEncoding.EncodeToString(k[:]) }

// startHome brings up the "home" side: a WireGuard peer on 127.0.0.1 whose LAN
// (console 192.168.1.1) exists only inside its own netstack. TCP port 7448
// echoes, TCP port 7447 streams bytes endlessly, UDP port 7449 echoes.
// Returns a client config for the app side (AllowedIPs = 192.168.1.0/24).
func startHome(t *testing.T, keepalive string) string {
	t.Helper()
	hPriv, hPub := keypair(t)
	aPriv, aPub := keypair(t)
	tdev, tnet, err := netstack.CreateNetTUN([]netip.Addr{consoleIP}, nil, 1420)
	if err != nil {
		t.Fatal(err)
	}
	dev := device.NewDevice(tdev, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	uapi := fmt.Sprintf("private_key=%s\nlisten_port=0\npublic_key=%s\nallowed_ip=192.168.2.2/32\n",
		hex.EncodeToString(hPriv[:]), hex.EncodeToString(aPub[:]))
	if err := dev.IpcSet(uapi); err != nil {
		t.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(dev.Close)
	raw, err := dev.IpcGet()
	if err != nil {
		t.Fatal(err)
	}
	port := 0
	for _, line := range strings.Split(raw, "\n") {
		if v, ok := strings.CutPrefix(line, "listen_port="); ok {
			port, _ = strconv.Atoi(v)
		}
	}
	if port == 0 {
		t.Fatalf("no listen port in %q", raw)
	}

	echo, err := tnet.ListenTCP(&net.TCPAddr{IP: consoleIP.AsSlice(), Port: 7448})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		for {
			c, err := echo.Accept()
			if err != nil {
				return
			}
			go func() { defer c.Close(); io.Copy(c, c) }()
		}
	}()
	stream, err := tnet.ListenTCP(&net.TCPAddr{IP: consoleIP.AsSlice(), Port: 7447})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		buf := make([]byte, 16*1024)
		for {
			c, err := stream.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				for {
					if _, err := c.Write(buf); err != nil {
						return
					}
				}
			}()
		}
	}()
	udpEcho, err := tnet.ListenUDP(&net.UDPAddr{IP: consoleIP.AsSlice(), Port: 7449})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		buf := make([]byte, 2048)
		for {
			n, from, err := udpEcho.ReadFrom(buf)
			if err != nil {
				return
			}
			udpEcho.WriteTo(buf[:n], from)
		}
	}()
	t.Cleanup(func() { echo.Close(); stream.Close(); udpEcho.Close() })

	return fmt.Sprintf("[Interface]\nPrivateKey = %s\nAddress = 192.168.2.2/32\n\n[Peer]\nPublicKey = %s\nAllowedIPs = 192.168.1.0/24\nEndpoint = 127.0.0.1:%d\n%s",
		b64(aPriv), b64(hPub), port, keepalive)
}

func startApp(t *testing.T, cfg string) *Tunnel {
	t.Helper()
	tun, err := Start(cfg, device.LogLevelSilent)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(tun.Close)
	return tun
}

func echoOnce(t *testing.T, port int) {
	t.Helper()
	c, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(10 * time.Second))
	if _, err := c.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, 4)
	if _, err := io.ReadFull(c, got); err != nil {
		t.Fatal(err)
	}
	if string(got) != "ping" {
		t.Fatalf("echo %q", got)
	}
}

func TestForwardIsIdempotentPerRemote(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	p1, err := tun.AddForward(0, "192.168.1.1", 7448)
	if err != nil {
		t.Fatal(err)
	}
	p2, err := tun.AddForward(0, "192.168.1.1", 7448)
	if err != nil {
		t.Fatal(err)
	}
	if p1 != p2 {
		t.Fatalf("second AddForward bound a new port: %d vs %d", p1, p2)
	}
	p3, err := tun.AddForward(0, "192.168.1.1", 7447)
	if err != nil {
		t.Fatal(err)
	}
	if p3 == p1 {
		t.Fatal("different remote must get its own port")
	}
	echoOnce(t, p1)
}

func TestDefaultKeepaliveWhenConfigHasNone(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	st, err := tun.Status()
	if err != nil {
		t.Fatal(err)
	}
	if len(st.Peers) != 1 || st.Peers[0].KeepaliveSecs != DefaultKeepalive {
		t.Fatalf("keepalive %+v", st.Peers)
	}
}

func TestExplicitKeepaliveIsKept(t *testing.T) {
	tun := startApp(t, startHome(t, "PersistentKeepalive = 10\n"))
	st, _ := tun.Status()
	if st.Peers[0].KeepaliveSecs != 10 {
		t.Fatalf("keepalive %d", st.Peers[0].KeepaliveSecs)
	}
}

func TestResetConnectionsClosesRelaysButKeepsPort(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	port, err := tun.AddForward(0, "192.168.1.1", 7447)
	if err != nil {
		t.Fatal(err)
	}
	c, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetReadDeadline(time.Now().Add(10 * time.Second))
	buf := make([]byte, 4096)
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatalf("stream before reset: %v", err)
	}
	if n := tun.ResetConnections(); n != 1 {
		t.Fatalf("closed %d relays, want 1", n)
	}
	// The local side must end promptly (EOF or reset), not hang.
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	for {
		if _, err := c.Read(buf); err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				t.Fatal("local connection still open after ResetConnections")
			}
			break
		}
	}
	// Same port works again.
	c2, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c2.Close()
	c2.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(c2, buf); err != nil {
		t.Fatalf("stream after reset: %v", err)
	}
}

func TestRebindKeepsTunnelWorking(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	port, err := tun.AddForward(0, "192.168.1.1", 7448)
	if err != nil {
		t.Fatal(err)
	}
	echoOnce(t, port)
	if err := tun.Rebind(); err != nil {
		t.Fatal(err)
	}
	echoOnce(t, port)
}

func TestForwardAfterCloseFails(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	tun.Close()
	if _, err := tun.AddForward(0, "192.168.1.1", 7448); err == nil {
		t.Fatal("AddForward on a closed tunnel must fail")
	}
}

// --- Hardening: forwards are loopback-only, limited to AllowedIPs, die with the tunnel.

func TestForwardRejectsTargetOutsideAllowedIPs(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	for _, host := range []string{"10.0.0.1", "192.168.2.1", "127.0.0.1", "fd00::1", "nonexistent.invalid"} {
		if p, err := tun.AddForward(0, host, 7448); err == nil {
			t.Errorf("AddForward to %s accepted (port %d)", host, p)
		}
	}
	for _, host := range []string{"10.0.0.1", "192.168.2.1", "127.0.0.1"} {
		if p, err := tun.AddUDPForward(0, host, 7449); err == nil {
			t.Errorf("AddUDPForward to %s accepted (port %d)", host, p)
		}
	}
	for _, port := range []int{0, -1, 70000} {
		if _, err := tun.AddForward(0, "192.168.1.1", port); err == nil {
			t.Errorf("AddForward to port %d accepted", port)
		}
	}
	if n := len(tun.listeners); n != 0 {
		t.Fatalf("rejected forwards left %d listeners open", n)
	}
	if _, err := tun.AddForward(0, "192.168.1.1", 7448); err != nil {
		t.Fatalf("target inside AllowedIPs rejected: %v", err)
	}
	if _, err := tun.AddUDPForward(0, "192.168.1.200", 7449); err != nil {
		t.Fatalf("UDP target inside AllowedIPs rejected: %v", err)
	}
}

func TestForwardListenersBindLoopbackOnly(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	if _, err := tun.AddForward(0, "192.168.1.1", 7448); err != nil {
		t.Fatal(err)
	}
	if _, err := tun.AddUDPForward(0, "192.168.1.1", 7449); err != nil {
		t.Fatal(err)
	}
	loopback := netip.MustParseAddr("127.0.0.1")
	checked := 0
	for _, c := range tun.listeners {
		var ap netip.AddrPort
		switch l := c.(type) {
		case net.Listener:
			ap = l.Addr().(*net.TCPAddr).AddrPort()
		case *net.UDPConn:
			ap = l.LocalAddr().(*net.UDPAddr).AddrPort()
		default:
			continue // tunnel-side sockets live in the netstack, not on the Mac
		}
		if ap.Addr().Unmap() != loopback {
			t.Errorf("listener bound to %s, want 127.0.0.1", ap)
		}
		checked++
	}
	if checked != 2 {
		t.Fatalf("checked %d local listeners, want 2", checked)
	}
}

func TestCloseClosesAllForwardListeners(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	tcpPort, err := tun.AddForward(0, "192.168.1.1", 7448)
	if err != nil {
		t.Fatal(err)
	}
	udpPort, err := tun.AddUDPForward(0, "192.168.1.1", 7449)
	if err != nil {
		t.Fatal(err)
	}
	tun.Close()
	if c, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(tcpPort), time.Second); err == nil {
		c.Close()
		t.Fatal("TCP forward still accepts connections after Close")
	}
	// Both ports must be free again: nothing of the tunnel survives Close.
	ln, err := net.Listen("tcp", "127.0.0.1:"+strconv.Itoa(tcpPort))
	if err != nil {
		t.Fatalf("TCP port still bound after Close: %v", err)
	}
	ln.Close()
	uc, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: udpPort})
	if err != nil {
		t.Fatalf("UDP port still bound after Close: %v", err)
	}
	uc.Close()
}

func udpSender(t *testing.T, port int) *net.UDPConn {
	t.Helper()
	c, err := net.DialUDP("udp", nil, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: port})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

// udpRoundTrip sends msg and waits for its echo; false if nothing came back in time.
func udpRoundTrip(t *testing.T, c *net.UDPConn, msg string, wait time.Duration) bool {
	t.Helper()
	if _, err := c.Write([]byte(msg)); err != nil {
		t.Fatal(err)
	}
	c.SetReadDeadline(time.Now().Add(wait))
	buf := make([]byte, 2048)
	n, err := c.Read(buf)
	if err != nil {
		return false
	}
	if string(buf[:n]) != msg {
		t.Fatalf("got %q, want %q", buf[:n], msg)
	}
	return true
}

func TestUDPForwardLocksToFirstSender(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	port, err := tun.AddUDPForward(0, "192.168.1.1", 7449)
	if err != nil {
		t.Fatal(err)
	}
	first := udpSender(t, port)
	// The first datagram may race the handshake; retry until any warm-up echo
	// arrives, then drain late echoes of earlier retries.
	buf := make([]byte, 2048)
	ok := false
	for i := 0; i < 20 && !ok; i++ {
		if _, err := first.Write([]byte("warmup")); err != nil {
			t.Fatal(err)
		}
		first.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
		n, err := first.Read(buf)
		ok = err == nil && string(buf[:n]) == "warmup"
	}
	if !ok {
		t.Fatal("no echo for the first sender")
	}
	for {
		first.SetReadDeadline(time.Now().Add(300 * time.Millisecond))
		if _, err := first.Read(buf); err != nil {
			break
		}
	}
	other := udpSender(t, port)
	if udpRoundTrip(t, other, "intruder", time.Second) {
		t.Fatal("a second local sender got a reply")
	}
	if got := tun.UDPForeignDropped.Load(); got != 1 {
		t.Fatalf("dropped %d foreign datagrams, want 1", got)
	}
	// The first sender keeps working and does not receive the intruder's echo.
	if !udpRoundTrip(t, first, "first-again", 5*time.Second) {
		t.Fatal("first sender lost its forward")
	}
}
