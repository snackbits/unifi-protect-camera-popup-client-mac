// app is the client side as the macOS app would run it: parse a wg-quick config,
// bring up the userspace tunnel, open local forwards on 127.0.0.1, run self tests.
package main

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/signal"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"golang.zx2c4.com/wireguard/device"

	"wgtunnel/tunnel"
)

const console = "192.168.1.1"
const camera = "192.168.1.50"

func must[T any](v T, err error) T {
	if err != nil {
		log.Fatal(err)
	}
	return v
}

func ms(d time.Duration) string { return fmt.Sprintf("%.3f ms", float64(d.Microseconds())/1000) }

func pctl(d []time.Duration) string {
	sort.Slice(d, func(i, j int) bool { return d[i] < d[j] })
	q := func(p float64) time.Duration { return d[int(float64(len(d)-1)*p)] }
	return fmt.Sprintf("n=%d min %s p50 %s p90 %s p99 %s max %s", len(d), ms(q(0)), ms(q(.5)), ms(q(.9)), ms(q(.99)), ms(q(1)))
}

func waitHandshake(t *tunnel.Tunnel) time.Duration {
	start := time.Now()
	// Handshake is triggered by the first packet; poke with a TCP dial.
	go func() {
		ctx, c := context.WithTimeout(context.Background(), 5*time.Second)
		defer c()
		if cn, err := t.DialContext(ctx, "tcp", console+":7448"); err == nil {
			cn.Close()
		}
	}()
	for time.Since(start) < 10*time.Second {
		st, _ := t.Status()
		if len(st.Peers) > 0 && st.Peers[0].LastHandshake > 0 {
			return time.Since(start)
		}
		time.Sleep(5 * time.Millisecond)
	}
	log.Fatal("kein Handshake nach 10 s")
	return 0
}

func httpTests(t *tunnel.Tunnel, fwdHTTPS int) {
	c := t.HTTPClient(true)
	for _, u := range []string{"https://" + console + "/proxy/protect/integration/v1/cameras", "http://" + console + "/proxy/protect/integration/v1/meta/info"} {
		req, _ := http.NewRequest("GET", u, nil)
		req.Header.Set("X-API-KEY", "test")
		t0 := time.Now()
		resp, err := c.Do(req)
		if err != nil {
			log.Printf("HTTP via netstack %s: FEHLER %v", u, err)
			continue
		}
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		log.Printf("HTTP via netstack %s -> %d %s in %s (inkl. TCP/TLS-Aufbau): %s", u, resp.StatusCode, resp.Proto, ms(time.Since(t0)), trunc(b))
	}
	// Same through the local forward with an ordinary client (as URLSession would).
	lc := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}}
	req, _ := http.NewRequest("GET", fmt.Sprintf("https://127.0.0.1:%d/proxy/protect/integration/v1/cameras", fwdHTTPS), nil)
	req.Header.Set("X-API-KEY", "test")
	t0 := time.Now()
	resp, err := lc.Do(req)
	if err != nil {
		log.Printf("HTTPS via Forward: FEHLER %v", err)
		return
	}
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	log.Printf("HTTPS via Forward 127.0.0.1:%d -> %d in %s: %s", fwdHTTPS, resp.StatusCode, ms(time.Since(t0)), trunc(b))
	// Keep-alive request latency (connection reused).
	var d []time.Duration
	for i := 0; i < 200; i++ {
		req, _ := http.NewRequest("GET", "https://"+console+"/proxy/protect/integration/v1/cameras", nil)
		req.Header.Set("X-API-KEY", "test")
		t0 := time.Now()
		resp, err := c.Do(req)
		if err != nil {
			log.Printf("HTTPS keepalive: %v", err)
			return
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		d = append(d, time.Since(t0))
	}
	log.Printf("HTTPS-Request (wiederverwendete Verbindung, netstack): %s", pctl(d))
}

func trunc(b []byte) string {
	if len(b) > 90 {
		return string(b[:90]) + "…"
	}
	return string(b)
}

func tcpRTT(t *tunnel.Tunnel, n int) {
	c := must(t.DialContext(context.Background(), "tcp", console+":7448"))
	defer c.Close()
	buf := make([]byte, 64)
	var d []time.Duration
	for i := 0; i < n; i++ {
		t0 := time.Now()
		c.Write(buf)
		if _, err := io.ReadFull(c, buf); err != nil {
			log.Printf("echo: %v", err)
			return
		}
		d = append(d, time.Since(t0))
	}
	log.Printf("TCP-RTT (64 B Echo durch Tunnel, netstack<->netstack): %s", pctl(d))
}

func icmpRTT(t *tunnel.Tunnel, n int) {
	pc, err := t.Net.DialPingAddr(netip.Addr{}, netip.MustParseAddr(console))
	if err != nil {
		log.Printf("ICMP: %v", err)
		return
	}
	defer pc.Close()
	var d []time.Duration
	lost := 0
	for i := 0; i < n; i++ {
		// ICMP echo request: type 8, code 0, checksum computed by gVisor? we compute.
		msg := []byte{8, 0, 0, 0, 0x12, 0x34, byte(i >> 8), byte(i), 'p', 'i', 'n', 'g'}
		cs := checksum(msg)
		msg[2], msg[3] = byte(cs>>8), byte(cs)
		t0 := time.Now()
		pc.SetReadDeadline(time.Now().Add(time.Second))
		if _, err := pc.Write(msg); err != nil {
			log.Printf("ICMP write: %v", err)
			return
		}
		rb := make([]byte, 1500)
		if _, err := pc.Read(rb); err != nil {
			lost++
			continue
		}
		d = append(d, time.Since(t0))
	}
	if len(d) == 0 {
		log.Printf("ICMP-Ping: keine Antworten (%d verloren)", lost)
		return
	}
	log.Printf("ICMP-Ping %s: %s, verloren %d", console, pctl(d), lost)
}

func checksum(b []byte) uint16 {
	var s uint32
	for i := 0; i+1 < len(b); i += 2 {
		s += uint32(b[i])<<8 | uint32(b[i+1])
	}
	if len(b)%2 == 1 {
		s += uint32(b[len(b)-1]) << 8
	}
	for s > 0xffff {
		s = s>>16 + s&0xffff
	}
	return ^uint16(s)
}

func throughputInternal(port int, dur time.Duration, streams int) float64 {
	var total atomic.Int64
	var wg sync.WaitGroup
	for i := 0; i < streams; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			c, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", port))
			if err != nil {
				log.Print(err)
				return
			}
			defer c.Close()
			c.SetReadDeadline(time.Now().Add(dur))
			n, _ := io.Copy(io.Discard, c)
			total.Add(n)
		}()
	}
	wg.Wait()
	return float64(total.Load()) * 8 / dur.Seconds() / 1e6
}

func getStats(t *tunnel.Tunnel, path string) map[string]any {
	resp, err := t.HTTPClient(true).Get("http://" + console + path)
	if err != nil {
		log.Printf("stats: %v", err)
		return nil
	}
	defer resp.Body.Close()
	var m map[string]any
	json.NewDecoder(resp.Body).Decode(&m)
	return m
}

// udpAudio sends n packets of size bytes every 20 ms to the local UDP forward.
func udpAudio(t *tunnel.Tunnel, fwdPort, n, size int, label string) {
	getStats(t, "/stats/reset")
	c := must(net.DialUDP("udp", nil, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: fwdPort}))
	defer c.Close()
	pkt := make([]byte, size)
	tick := time.NewTicker(20 * time.Millisecond)
	defer tick.Stop()
	var jitterMax time.Duration
	last := time.Now()
	for i := 0; i < n; i++ {
		<-tick.C
		now := time.Now()
		if i > 0 {
			if j := now.Sub(last) - 20*time.Millisecond; j > jitterMax {
				jitterMax = j
			} else if -j > jitterMax {
				jitterMax = -j
			}
		}
		last = now
		binary.BigEndian.PutUint32(pkt[0:4], uint32(i))
		binary.BigEndian.PutUint64(pkt[4:12], uint64(now.UnixNano()))
		if _, err := c.Write(pkt); err != nil {
			log.Printf("udp write: %v", err)
		}
	}
	time.Sleep(300 * time.Millisecond)
	s := getStats(t, "/stats")
	recv := int(s["received"].(float64))
	log.Printf("UDP %s: gesendet %d x %d B im 20-ms-Takt, empfangen %d, Verlust %d (%.2f %%), dup %v, reorder %v, One-Way p50 %.3f ms p99 %.3f ms max %.3f ms, Sender-Taktabweichung max %s",
		label, n, size, recv, n-recv, 100*float64(n-recv)/float64(n), s["duplicates"], s["reordered"],
		s["oneWayMs_p50"], s["oneWayMs_p99"], s["oneWayMs_max"], ms(jitterMax))
}

func udpEchoRTT(fwdPort, n int) {
	c := must(net.DialUDP("udp", nil, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: fwdPort}))
	defer c.Close()
	var d []time.Duration
	lost := 0
	b := make([]byte, 200)
	for i := 0; i < n; i++ {
		t0 := time.Now()
		c.Write(b[:160])
		c.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
		if _, err := c.Read(b); err != nil {
			lost++
			continue
		}
		d = append(d, time.Since(t0))
	}
	if len(d) > 0 {
		log.Printf("UDP-RTT über lokalen UDP-Forward 127.0.0.1:%d -> %s:7005 (Echo): %s, verloren %d", fwdPort, camera, pctl(d), lost)
	} else {
		log.Printf("UDP-RTT: alles verloren (%d)", lost)
	}
}

func main() {
	cfgPath := flag.String("config", "app.conf", "wg-quick config")
	selftest := flag.Bool("selftest", true, "run built-in measurements")
	hold := flag.Bool("hold", false, "keep forwards open until SIGINT")
	verbose := flag.Bool("v", false, "verbose wireguard log")
	flag.Parse()

	txt := must(os.ReadFile(*cfgPath))
	lvl := device.LogLevelError
	if *verbose {
		lvl = device.LogLevelVerbose
	}
	t0 := time.Now()
	t := must(tunnel.Start(string(txt), lvl))
	defer t.Close()
	log.Printf("Tunnel gestartet in %s (MTU %d)", ms(time.Since(t0)), t.Config.MTUOrDefault())
	log.Printf("Handshake nach %s", ms(waitHandshake(t)))

	p7447 := must(t.AddForward(17447, console, 7447))
	p443 := must(t.AddForward(18443, console, 443))
	p80 := must(t.AddForward(18080, console, 80))
	p7448 := must(t.AddForward(17448, console, 7448))
	u7004 := must(t.AddUDPForward(17004, camera, 7004))
	u7005 := must(t.AddUDPForward(17005, camera, 7005))
	log.Printf("Forwards: tcp 127.0.0.1:%d->%s:7447, :%d->:443, :%d->:80, :%d->:7448 echo; udp :%d->%s:7004, :%d->:7005 echo",
		p7447, console, p443, p80, p7448, u7004, camera, u7005)

	if *selftest {
		httpTests(t, p443)
		tcpRTT(t, 2000)
		icmpRTT(t, 200)
		udpEchoRTT(u7005, 500)
		for _, s := range []int{1, 4} {
			log.Printf("Durchsatz Forward 127.0.0.1:%d (Go-Client, 10 s, %d Stream(s)): %.1f Mbit/s", p7447, s, throughputInternal(p7447, 10*time.Second, s))
		}
		udpAudio(t, u7004, 500, 172, "Ruhe (10 s)")
		// Audio while a full-speed TCP download saturates the tunnel.
		stop := make(chan float64)
		go func() { stop <- throughputInternal(p7447, 11*time.Second, 1) }()
		time.Sleep(200 * time.Millisecond)
		udpAudio(t, u7004, 500, 172, "unter Volllast-TCP (10 s)")
		log.Printf("  ... parallel TCP-Durchsatz: %.1f Mbit/s", <-stop)
		st, _ := t.Status()
		b, _ := json.Marshal(st)
		log.Printf("Status: %s", b)
	}
	if *hold {
		log.Printf("halte Forwards offen (Ctrl-C beendet)")
		ch := make(chan os.Signal, 1)
		signal.Notify(ch, os.Interrupt)
		<-ch
		st, _ := t.Status()
		b, _ := json.Marshal(st)
		log.Printf("Status bei Ende: %s", b)
	}
}
