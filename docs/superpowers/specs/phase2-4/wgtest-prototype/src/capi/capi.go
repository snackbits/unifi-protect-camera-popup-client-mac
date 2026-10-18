// Package main is the C API exported via -buildmode=c-archive.
// All returned char* must be released with WgFree.
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
// Returns the bound local port or -1 (see WgLastError).
//
//export WgAddForward
func WgAddForward(localPort C.int, remoteHost *C.char, remotePort C.int) C.int {
	h := C.GoString(remoteHost)
	return withTunnel(func(t *tunnel.Tunnel) (int, error) { return t.AddForward(int(localPort), h, int(remotePort)) })
}

// WgAddUDPForward: same for UDP (remoteHost must be an IP literal).
//
//export WgAddUDPForward
func WgAddUDPForward(localPort C.int, remoteHost *C.char, remotePort C.int) C.int {
	h := C.GoString(remoteHost)
	return withTunnel(func(t *tunnel.Tunnel) (int, error) { return t.AddUDPForward(int(localPort), h, int(remotePort)) })
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
		return C.CString(`{"up":true,"error":` + quote(err.Error()) + `}`)
	}
	b, _ := json.Marshal(st)
	return C.CString(string(b))
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

func quote(s string) string { b, _ := json.Marshal(s); return string(b) }

func main() {}
