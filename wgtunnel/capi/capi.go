// Package main is the C API exported via -buildmode=c-archive.
// The hand-written header wgtunnel/include/wgtunnel.h declares these functions
// for Swift; keep both in sync. All returned char* must be released with WgFree.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"errors"
	"sync"
	"unsafe"

	"golang.zx2c4.com/wireguard/device"

	"wgtunnel/tunnel"
	"wgtunnel/wgconf"
)

var (
	mu      sync.Mutex
	cur     *tunnel.Tunnel
	lastErr string
)

func setErr(err error) {
	if err != nil {
		lastErr = err.Error()
	} else {
		lastErr = ""
	}
}

func jsonString(v any) *C.char {
	b, _ := json.Marshal(v)
	return C.CString(string(b))
}

// WgParse validates a wg-quick config without starting anything.
// Returns {"ok":true,"summary":{...}} or {"ok":false,"error":"Zeile 3: ..."}.
//
//export WgParse
func WgParse(config *C.char) *C.char {
	cfg, err := wgconf.Parse(C.GoString(config))
	if err != nil {
		return jsonString(map[string]any{"ok": false, "error": err.Error()})
	}
	return jsonString(map[string]any{"ok": true, "summary": cfg.Summary()})
}

// WgStart parses a wg-quick config and starts the tunnel.
// Returns NULL on success, otherwise an error message.
//
//export WgStart
func WgStart(config *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	if cur != nil {
		return C.CString("Tunnel läuft bereits")
	}
	t, err := tunnel.Start(C.GoString(config), device.LogLevelError)
	setErr(err)
	if err != nil {
		return C.CString(err.Error())
	}
	cur = t
	return nil
}

// WgStop closes the tunnel and every forward listener and relayed connection.
//
//export WgStop
func WgStop() {
	mu.Lock()
	defer mu.Unlock()
	if cur != nil {
		cur.Close()
		cur = nil
	}
}

func withTunnel(f func(t *tunnel.Tunnel) (int, error)) C.int {
	mu.Lock()
	defer mu.Unlock()
	if cur == nil {
		setErr(errors.New("Tunnel nicht gestartet"))
		return -1
	}
	p, err := f(cur)
	setErr(err)
	if err != nil {
		return -1
	}
	return C.int(p)
}

// WgAddForward opens 127.0.0.1:localPort (0 = pick free port) -> remoteHost:remotePort (TCP).
// The same remote always gets the same port while the tunnel runs. remoteHost
// must be (or resolve to) an address inside the peer's AllowedIPs, otherwise -1.
// Returns the bound local port or -1 (see WgLastError).
//
//export WgAddForward
func WgAddForward(localPort C.int, remoteHost *C.char, remotePort C.int) C.int {
	h := C.GoString(remoteHost)
	return withTunnel(func(t *tunnel.Tunnel) (int, error) { return t.AddForward(int(localPort), h, int(remotePort)) })
}

// WgAddUDPForward: same for UDP (remoteHost must be an IP literal inside
// AllowedIPs). One local sender at a time: others are dropped until it has been
// silent for 3 s, or WgResetConnections or WgReleaseUDPForward ran.
//
//export WgAddUDPForward
func WgAddUDPForward(localPort C.int, remoteHost *C.char, remotePort C.int) C.int {
	h := C.GoString(remoteHost)
	return withTunnel(func(t *tunnel.Tunnel) (int, error) { return t.AddUDPForward(int(localPort), h, int(remotePort)) })
}

// WgReleaseUDPForward unlocks the UDP forward on 127.0.0.1:localPort for the
// next local sender (call right before a new talkback session starts on it).
// Returns 0, or -1 when the tunnel is not running or has no such forward
// (see WgLastError).
//
//export WgReleaseUDPForward
func WgReleaseUDPForward(localPort C.int) C.int {
	return withTunnel(func(t *tunnel.Tunnel) (int, error) { return 0, t.ReleaseUDPForward(int(localPort)) })
}

// WgResetConnections closes all relayed TCP connections (listeners stay) and
// unlocks every UDP forward for the next local sender.
// Returns the number closed, 0 when the tunnel is not running.
//
//export WgResetConnections
func WgResetConnections() C.int {
	mu.Lock()
	defer mu.Unlock()
	if cur == nil {
		return 0
	}
	return C.int(cur.ResetConnections())
}

// WgRebind re-resolves endpoints and rebinds the UDP socket after a network change.
// Returns NULL on success, otherwise an error message.
//
//export WgRebind
func WgRebind() *C.char {
	mu.Lock()
	t := cur
	mu.Unlock()
	if t == nil {
		return C.CString("Tunnel nicht gestartet")
	}
	// Outside the lock: the DNS lookup may take seconds, forwards must not wait for it.
	if err := t.Rebind(); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

// WgReresolve looks up the endpoint host names again (same network, peer silent)
// and moves a peer only when its address changed. Returns
// {"updates":[{"host":"…","ip":"…","changed":true}]} (empty for IP endpoints)
// or {"error":"…","updates":[…]}.
//
//export WgReresolve
func WgReresolve() *C.char {
	mu.Lock()
	t := cur
	mu.Unlock()
	if t == nil {
		return jsonString(map[string]any{"error": "Tunnel nicht gestartet", "updates": []tunnel.EndpointUpdate{}})
	}
	// Outside the lock, like WgRebind: the DNS lookup may take seconds.
	updates, err := t.Reresolve()
	if updates == nil {
		updates = []tunnel.EndpointUpdate{}
	}
	if err != nil {
		return jsonString(map[string]any{"error": err.Error(), "updates": updates})
	}
	return jsonString(map[string]any{"updates": updates})
}

// WgStatus returns a JSON document ({"up":false} when stopped).
//
//export WgStatus
func WgStatus() *C.char {
	mu.Lock()
	defer mu.Unlock()
	if cur == nil {
		return C.CString(`{"up":false}`)
	}
	st, err := cur.Status()
	if err != nil {
		return jsonString(map[string]any{"up": true, "error": err.Error()})
	}
	return jsonString(st)
}

//export WgLastError
func WgLastError() *C.char {
	mu.Lock()
	defer mu.Unlock()
	if lastErr == "" {
		return nil
	}
	return C.CString(lastErr)
}

//export WgFree
func WgFree(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}
