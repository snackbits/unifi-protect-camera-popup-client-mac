// udprelay sits between app and home to simulate network events:
// SIGUSR1 toggles a full blackout (sleep / Wi-Fi gone), SIGUSR2 rebinds the
// outbound socket so home sees a new source port (client roaming / NAT rebind).
package main

import (
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:51821", "")
	target := flag.String("target", "127.0.0.1:51820", "")
	flag.Parse()
	in, err := net.ListenPacket("udp", *listen)
	if err != nil {
		log.Fatal(err)
	}
	taddr, _ := net.ResolveUDPAddr("udp", *target)
	var drop atomic.Bool
	var client atomic.Pointer[net.Addr]
	var mu sync.Mutex
	var out *net.UDPConn
	var dropped, fwd atomic.Int64

	bind := func() {
		c, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
		if err != nil {
			log.Fatal(err)
		}
		mu.Lock()
		old := out
		out = c
		mu.Unlock()
		if old != nil {
			old.Close()
		}
		log.Printf("outbound socket %s", c.LocalAddr())
		go func() {
			b := make([]byte, 65535)
			for {
				n, err := c.Read(b)
				if err != nil {
					return
				}
				if drop.Load() {
					dropped.Add(1)
					continue
				}
				if a := client.Load(); a != nil {
					in.WriteTo(b[:n], *a)
				}
			}
		}()
	}
	bind()

	sig := make(chan os.Signal, 4)
	signal.Notify(sig, syscall.SIGUSR1, syscall.SIGUSR2)
	go func() {
		for s := range sig {
			if s == syscall.SIGUSR1 {
				drop.Store(!drop.Load())
				log.Printf("blackout=%v (dropped so far %d, forwarded %d)", drop.Load(), dropped.Load(), fwd.Load())
			} else {
				bind()
			}
		}
	}()
	b := make([]byte, 65535)
	for {
		n, a, err := in.ReadFrom(b)
		if err != nil {
			log.Fatal(err)
		}
		client.Store(&a)
		if drop.Load() {
			dropped.Add(1)
			continue
		}
		mu.Lock()
		c := out
		mu.Unlock()
		c.WriteToUDP(b[:n], taddr)
		fwd.Add(1)
	}
}
