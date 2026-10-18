// home simulates the UniFi side: a WireGuard "server" peer whose LAN only exists
// inside a gVisor netstack. Console 192.168.1.1 (HTTP :80, HTTPS :443, RTSP-like
// TCP :7447, TCP echo :7448), camera 192.168.1.50 (UDP sink :7004, UDP echo :7005).
// It writes app.conf (wg-quick format, like a UniFi export) for the client.
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/netip"
	"os"
	"sort"
	"sync"
	"time"

	"golang.org/x/crypto/curve25519"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

var (
	keyN      int
	consoleIP = netip.MustParseAddr("192.168.1.1")
	cameraIP  = netip.MustParseAddr("192.168.1.50")
	appIP     = "192.168.2.2"
)

var seed string

func keypair() (priv, pub [32]byte) {
	if seed != "" { // deterministic keys so a restarted home keeps its identity
		priv = sha256.Sum256([]byte(seed + fmt.Sprint(keyN)))
		keyN++
	} else {
		rand.Read(priv[:])
	}
	priv[0] &= 248
	priv[31] = (priv[31] & 127) | 64
	p, _ := curve25519.X25519(priv[:], curve25519.Basepoint)
	copy(pub[:], p)
	return
}

func b64(k [32]byte) string { return base64.StdEncoding.EncodeToString(k[:]) }

type udpStats struct {
	mu      sync.Mutex
	recv    int
	dup     int
	reorder int
	maxSeq  int64
	seen    map[uint32]bool
	lat     []time.Duration // one-way (same host clock)
	firstAt time.Time
	lastAt  time.Time
	bytes   int
}

func (s *udpStats) reset() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.recv, s.dup, s.reorder, s.bytes, s.maxSeq = 0, 0, 0, 0, -1
	s.seen, s.lat = map[uint32]bool{}, nil
	s.firstAt, s.lastAt = time.Time{}, time.Time{}
}

func (s *udpStats) add(b []byte) {
	if len(b) < 12 {
		return
	}
	seq := binary.BigEndian.Uint32(b[0:4])
	sent := int64(binary.BigEndian.Uint64(b[4:12]))
	now := time.Now()
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.seen[seq] {
		s.dup++
		return
	}
	s.seen[seq] = true
	s.recv++
	s.bytes += len(b)
	if int64(seq) < s.maxSeq {
		s.reorder++
	} else {
		s.maxSeq = int64(seq)
	}
	s.lat = append(s.lat, now.Sub(time.Unix(0, sent)))
	if s.firstAt.IsZero() {
		s.firstAt = now
	}
	s.lastAt = now
}

func pct(d []time.Duration, p float64) float64 {
	if len(d) == 0 {
		return 0
	}
	i := int(float64(len(d)-1) * p)
	return float64(d[i].Microseconds()) / 1000
}

func (s *udpStats) snapshot() map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	l := append([]time.Duration(nil), s.lat...)
	sort.Slice(l, func(i, j int) bool { return l[i] < l[j] })
	return map[string]any{
		"received": s.recv, "duplicates": s.dup, "reordered": s.reorder,
		"maxSeq": s.maxSeq, "bytes": s.bytes,
		"oneWayMs_p50": pct(l, .5), "oneWayMs_p99": pct(l, .99), "oneWayMs_max": pct(l, 1),
		"spanMs": s.lastAt.Sub(s.firstAt).Milliseconds(),
	}
}

func selfSigned() tls.Certificate {
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tpl := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "unifi.local"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(24 * time.Hour),
		IPAddresses: []net.IP{consoleIP.AsSlice()}, DNSNames: []string{"unifi.local"},
	}
	der, _ := x509.CreateCertificate(rand.Reader, tpl, tpl, &k.PublicKey, k)
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: k}
}

func main() {
	listen := flag.Int("port", 51820, "UDP listen port (real socket)")
	out := flag.String("out", "app.conf", "write client config here")
	mtu := flag.Int("mtu", 1420, "tunnel MTU")
	verbose := flag.Bool("v", false, "verbose wireguard log")
	flag.StringVar(&seed, "seed", "", "derive keys from seed (stable across restarts)")
	flag.Parse()

	hPriv, hPub := keypair()
	aPriv, aPub := keypair()
	psk, _ := keypair()

	tdev, tnet, err := netstack.CreateNetTUN([]netip.Addr{consoleIP, cameraIP}, nil, *mtu)
	if err != nil {
		log.Fatal(err)
	}
	lvl := device.LogLevelError
	if *verbose {
		lvl = device.LogLevelVerbose
	}
	dev := device.NewDevice(tdev, conn.NewDefaultBind(), device.NewLogger(lvl, "home: "))
	uapi := fmt.Sprintf("private_key=%s\nlisten_port=%d\npublic_key=%s\npreshared_key=%s\nallowed_ip=%s/32\n",
		hex.EncodeToString(hPriv[:]), *listen, hex.EncodeToString(aPub[:]), hex.EncodeToString(psk[:]), appIP)
	if err := dev.IpcSet(uapi); err != nil {
		log.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		log.Fatal(err)
	}

	appConf := fmt.Sprintf(`[Interface]
PrivateKey = %s
Address = %s/32
DNS = 192.168.1.1
MTU = %d

[Peer]
PublicKey = %s
PresharedKey = %s
AllowedIPs = 192.168.1.0/24
Endpoint = 127.0.0.1:%d
PersistentKeepalive = 25
`, b64(aPriv), appIP, *mtu, b64(hPub), b64(psk), *listen)
	if err := os.WriteFile(*out, []byte(appConf), 0600); err != nil {
		log.Fatal(err)
	}

	stats := &udpStats{}
	stats.reset()

	mux := http.NewServeMux()
	mux.HandleFunc("/proxy/protect/integration/v1/meta/info", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-API-KEY") == "" {
			http.Error(w, `{"error":"missing X-API-KEY"}`, 401)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, `{"applicationVersion":"6.0.0-fake"}`)
	})
	mux.HandleFunc("/proxy/protect/integration/v1/cameras", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-API-KEY") == "" {
			http.Error(w, `{"error":"missing X-API-KEY"}`, 401)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, `[{"id":"66aa00000000000000000001","modelKey":"camera","name":"Haustür","state":"CONNECTED","featureFlags":{"hasSpeaker":true,"hasMic":true}},`+
			`{"id":"66aa00000000000000000002","modelKey":"camera","name":"Garten","state":"CONNECTED","featureFlags":{"hasSpeaker":false,"hasMic":true}}]`)
	})
	mux.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(stats.snapshot())
	})
	mux.HandleFunc("/stats/reset", func(w http.ResponseWriter, r *http.Request) {
		stats.reset()
		io.WriteString(w, "ok\n")
	})

	l80, err := tnet.ListenTCP(&net.TCPAddr{IP: consoleIP.AsSlice(), Port: 80})
	if err != nil {
		log.Fatal(err)
	}
	go http.Serve(l80, mux)
	l443, err := tnet.ListenTCP(&net.TCPAddr{IP: consoleIP.AsSlice(), Port: 443})
	if err != nil {
		log.Fatal(err)
	}
	go http.Serve(tls.NewListener(l443, &tls.Config{Certificates: []tls.Certificate{selfSigned()}}), mux)

	// 7447: endless byte source (stand-in for an RTSP/RTP-over-TCP stream).
	l7447, err := tnet.ListenTCP(&net.TCPAddr{IP: consoleIP.AsSlice(), Port: 7447})
	if err != nil {
		log.Fatal(err)
	}
	go func() {
		buf := make([]byte, 64*1024)
		rand.Read(buf)
		for {
			c, err := l7447.Accept()
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
	// 7448: TCP echo (RTT).
	l7448, err := tnet.ListenTCP(&net.TCPAddr{IP: consoleIP.AsSlice(), Port: 7448})
	if err != nil {
		log.Fatal(err)
	}
	go func() {
		for {
			c, err := l7448.Accept()
			if err != nil {
				return
			}
			go func() { defer c.Close(); io.Copy(c, c) }()
		}
	}()
	// Camera UDP 7004 sink, 7005 echo.
	u7004, err := tnet.ListenUDP(&net.UDPAddr{IP: cameraIP.AsSlice(), Port: 7004})
	if err != nil {
		log.Fatal(err)
	}
	go func() {
		b := make([]byte, 65535)
		for {
			n, _, err := u7004.ReadFrom(b)
			if err != nil {
				return
			}
			stats.add(b[:n])
		}
	}()
	u7005, err := tnet.ListenUDP(&net.UDPAddr{IP: cameraIP.AsSlice(), Port: 7005})
	if err != nil {
		log.Fatal(err)
	}
	go func() {
		b := make([]byte, 65535)
		for {
			n, a, err := u7005.ReadFrom(b)
			if err != nil {
				return
			}
			u7005.WriteTo(b[:n], a)
		}
	}()

	log.Printf("home up: udp :%d, console %s, camera %s, client config -> %s", *listen, consoleIP, cameraIP, *out)
	select {}
}
