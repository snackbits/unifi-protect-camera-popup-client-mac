// Package wgconf parses WireGuard client configurations in wg-quick format,
// as exported by UniFi gateways ("Download config"), and converts them to the
// UAPI text format understood by wireguard-go's Device.IpcSet.
package wgconf

import (
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/netip"
	"strconv"
	"strings"
)

type Key [32]byte

func (k Key) Hex() string    { return hex.EncodeToString(k[:]) }
func (k Key) Base64() string { return base64.StdEncoding.EncodeToString(k[:]) }
func (k Key) IsZero() bool   { return k == Key{} }

// A Key never shows its bytes when formatted or encoded: Format covers every
// fmt verb (%v, %+v, %#v, %s, %x, %d, %o, %b …, also inside structs and
// slices), MarshalText covers encoding/json and friends. Use Hex or Base64
// where the key is really needed.
const redacted = "<redacted>"

func (k Key) String() string               { return redacted }
func (k Key) GoString() string             { return redacted }
func (k Key) Format(f fmt.State, _ rune)   { io.WriteString(f, redacted) }
func (k Key) MarshalText() ([]byte, error) { return []byte(redacted), nil }

type Interface struct {
	PrivateKey Key
	Addresses  []netip.Prefix
	DNS        []netip.Addr
	DNSSearch  []string // non-IP entries in DNS= are search domains (wg-quick semantics)
	MTU        int      // 0 = not set
	ListenPort int      // 0 = not set
}

type Peer struct {
	PublicKey           Key
	PresharedKey        Key
	HasPresharedKey     bool
	AllowedIPs          []netip.Prefix
	EndpointHost        string // hostname or IP literal, without brackets
	EndpointPort        uint16
	PersistentKeepalive int // seconds, 0 = off
}

func (p Peer) Endpoint() string {
	return net.JoinHostPort(p.EndpointHost, strconv.Itoa(int(p.EndpointPort)))
}

type Config struct {
	Interface Interface
	Peers     []Peer
	Warnings  []string // ignored wg-quick-only keys etc.
}

// ParseError carries the 1-based line number of the problem.
type ParseError struct {
	Line int
	Msg  string
}

func (e *ParseError) Error() string {
	if e.Line > 0 {
		return fmt.Sprintf("Zeile %d: %s", e.Line, e.Msg)
	}
	return e.Msg
}

func errAt(line int, format string, a ...any) error {
	return &ParseError{Line: line, Msg: fmt.Sprintf(format, a...)}
}

// unknownKey describes a key that is not understood. Only plain names are
// quoted: a stray line of key material ("base64…=") parses as a "key" too,
// and an error message must never echo it.
func unknownKey(key, section string) string {
	if isPlainName(key) {
		return fmt.Sprintf("unbekannter Schlüssel %q in %s", key, section)
	}
	return "unbekannte Zeile in " + section
}

// isPlainName reports whether key consists of ASCII letters only (^[A-Za-z]+$).
func isPlainName(key string) bool {
	if key == "" {
		return false
	}
	for _, r := range key {
		if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') {
			return false
		}
	}
	return true
}

// Keys only meaningful for wg-quick on a real interface. They are accepted and ignored.
var ignoredInterfaceKeys = map[string]bool{
	"table": true, "preup": true, "postup": true, "predown": true, "postdown": true,
	"saveconfig": true, "fwmark": true,
}

func ParseKey(s string) (Key, error) {
	var k Key
	b, err := base64.StdEncoding.DecodeString(strings.TrimSpace(s))
	if err != nil {
		return k, fmt.Errorf("Schlüssel ist kein gültiges Base64")
	}
	if len(b) != 32 {
		return k, fmt.Errorf("Schlüssel hat %d statt 32 Bytes", len(b))
	}
	copy(k[:], b)
	return k, nil
}

func splitList(v string) []string {
	var out []string
	for _, p := range strings.Split(v, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func parsePrefix(s string, isAddress bool) (netip.Prefix, error) {
	if strings.Contains(s, "/") {
		p, err := netip.ParsePrefix(s)
		if err != nil {
			return p, err
		}
		if !isAddress {
			p = p.Masked()
		}
		return p, nil
	}
	a, err := netip.ParseAddr(s)
	if err != nil {
		return netip.Prefix{}, err
	}
	return netip.PrefixFrom(a, a.BitLen()), nil
}

func parseEndpoint(s string) (string, uint16, error) {
	host, port, err := net.SplitHostPort(s)
	if err != nil {
		return "", 0, fmt.Errorf("Endpoint %q: erwartet host:port bzw. [IPv6]:port", s)
	}
	if host == "" {
		return "", 0, fmt.Errorf("Endpoint %q: Host fehlt", s)
	}
	n, err := strconv.ParseUint(port, 10, 16)
	if err != nil || n == 0 {
		return "", 0, fmt.Errorf("Endpoint %q: ungültiger Port", s)
	}
	return host, uint16(n), nil
}

// Parse parses wg-quick formatted text.
func Parse(text string) (*Config, error) {
	text = strings.TrimPrefix(text, "\ufeff")
	cfg := &Config{}
	section := ""
	var peer *Peer
	sawInterface := false
	seenIface := map[string]int{}
	var seenPeer map[string]int
	peerLines := []int{}

	for i, raw := range strings.Split(text, "\n") {
		ln := i + 1
		line := strings.TrimRight(raw, "\r")
		if idx := strings.IndexByte(line, '#'); idx >= 0 {
			line = line[:idx]
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") {
			if !strings.HasSuffix(line, "]") {
				return nil, errAt(ln, "Abschnittskopf %q nicht geschlossen", line)
			}
			name := strings.ToLower(strings.TrimSpace(line[1 : len(line)-1]))
			switch name {
			case "interface":
				if sawInterface {
					return nil, errAt(ln, "[Interface] mehrfach vorhanden")
				}
				sawInterface = true
				section = "interface"
			case "peer":
				cfg.Peers = append(cfg.Peers, Peer{})
				peer = &cfg.Peers[len(cfg.Peers)-1]
				seenPeer = map[string]int{}
				peerLines = append(peerLines, ln)
				section = "peer"
			default:
				return nil, errAt(ln, "unbekannter Abschnitt %q", line)
			}
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq < 0 {
			return nil, errAt(ln, "erwartet Schlüssel = Wert")
		}
		key := strings.ToLower(strings.TrimSpace(line[:eq]))
		val := strings.TrimSpace(line[eq+1:])
		if key == "" {
			return nil, errAt(ln, "Schlüsselname fehlt")
		}
		if section == "" {
			if !isPlainName(key) {
				return nil, errAt(ln, "unbekannte Zeile vor dem ersten Abschnitt")
			}
			return nil, errAt(ln, "%q steht vor dem ersten Abschnitt", key)
		}
		// Keys that may legitimately appear multiple times (values are merged).
		multi := key == "address" || key == "dns" || key == "allowedips"
		seen := seenIface
		if section == "peer" {
			seen = seenPeer
		}
		if prev, ok := seen[key]; ok && !multi && isPlainName(key) {
			return nil, errAt(ln, "%q doppelt (zuerst in Zeile %d)", key, prev)
		}
		seen[key] = ln

		if section == "interface" {
			ifc := &cfg.Interface
			switch key {
			case "privatekey":
				if strings.TrimSpace(val) == "" {
					// UniFi leaves it empty for clients with a custom public key.
					return nil, errAt(ln, "PrivateKey ist leer – die Datei enthält keinen privaten Schlüssel. "+
						"In UniFi beim Client den Schlüssel neu erzeugen lassen und die Datei erneut herunterladen")
				}
				k, err := ParseKey(val)
				if err != nil {
					return nil, errAt(ln, "PrivateKey: %v", err)
				}
				ifc.PrivateKey = k
			case "address":
				for _, s := range splitList(val) {
					p, err := parsePrefix(s, true)
					if err != nil {
						return nil, errAt(ln, "Address %q ungültig", s)
					}
					ifc.Addresses = append(ifc.Addresses, p)
				}
			case "dns":
				for _, s := range splitList(val) {
					if a, err := netip.ParseAddr(s); err == nil {
						ifc.DNS = append(ifc.DNS, a)
					} else {
						ifc.DNSSearch = append(ifc.DNSSearch, s)
					}
				}
			case "mtu":
				n, err := strconv.Atoi(val)
				if err != nil || n < 576 || n > 9000 {
					return nil, errAt(ln, "MTU %q ungültig (576–9000)", val)
				}
				ifc.MTU = n
			case "listenport":
				n, err := strconv.ParseUint(val, 10, 16)
				if err != nil {
					return nil, errAt(ln, "ListenPort %q ungültig", val)
				}
				ifc.ListenPort = int(n)
			default:
				if ignoredInterfaceKeys[key] {
					cfg.Warnings = append(cfg.Warnings, fmt.Sprintf("Zeile %d: %q wird ignoriert", ln, key))
					continue
				}
				return nil, errAt(ln, "%s", unknownKey(key, "[Interface]"))
			}
		} else {
			switch key {
			case "publickey":
				k, err := ParseKey(val)
				if err != nil {
					return nil, errAt(ln, "PublicKey: %v", err)
				}
				peer.PublicKey = k
			case "presharedkey":
				k, err := ParseKey(val)
				if err != nil {
					return nil, errAt(ln, "PresharedKey: %v", err)
				}
				peer.PresharedKey, peer.HasPresharedKey = k, true
			case "allowedips":
				for _, s := range splitList(val) {
					p, err := parsePrefix(s, false)
					if err != nil {
						return nil, errAt(ln, "AllowedIPs %q ungültig", s)
					}
					peer.AllowedIPs = append(peer.AllowedIPs, p)
				}
			case "endpoint":
				h, p, err := parseEndpoint(val)
				if err != nil {
					return nil, errAt(ln, "%v", err)
				}
				peer.EndpointHost, peer.EndpointPort = h, p
			case "persistentkeepalive":
				if strings.EqualFold(val, "off") {
					peer.PersistentKeepalive = 0
					continue
				}
				n, err := strconv.ParseUint(val, 10, 16)
				if err != nil {
					return nil, errAt(ln, "PersistentKeepalive %q ungültig (0–65535 oder off)", val)
				}
				peer.PersistentKeepalive = int(n)
			default:
				return nil, errAt(ln, "%s", unknownKey(key, "[Peer]"))
			}
		}
	}

	if !sawInterface {
		return nil, errAt(0, "[Interface]-Abschnitt fehlt")
	}
	if cfg.Interface.PrivateKey.IsZero() {
		return nil, errAt(0, "PrivateKey fehlt in [Interface]")
	}
	if len(cfg.Interface.Addresses) == 0 {
		return nil, errAt(0, "Address fehlt in [Interface] (ohne Tunnel-IP kein netstack)")
	}
	if len(cfg.Peers) == 0 {
		return nil, errAt(0, "kein [Peer]-Abschnitt")
	}
	pubs := map[Key]bool{}
	for i, p := range cfg.Peers {
		ln := peerLines[i]
		if p.PublicKey.IsZero() {
			return nil, errAt(ln, "PublicKey fehlt in [Peer]")
		}
		if pubs[p.PublicKey] {
			return nil, errAt(ln, "PublicKey doppelt")
		}
		pubs[p.PublicKey] = true
		if len(p.AllowedIPs) == 0 {
			return nil, errAt(ln, "AllowedIPs fehlt in [Peer]")
		}
		if p.EndpointHost == "" {
			return nil, errAt(ln, "Endpoint fehlt in [Peer] (Client braucht Ziel)")
		}
	}
	return cfg, nil
}

// UAPI renders the device configuration for wireguard-go's IpcSet.
// resolve maps EndpointHost to an IP (DNS lookup happens outside the tunnel).
func (c *Config) UAPI(resolve func(host string) (netip.Addr, error)) (string, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "private_key=%s\n", c.Interface.PrivateKey.Hex())
	if c.Interface.ListenPort != 0 {
		fmt.Fprintf(&b, "listen_port=%d\n", c.Interface.ListenPort)
	}
	b.WriteString("replace_peers=true\n")
	for _, p := range c.Peers {
		fmt.Fprintf(&b, "public_key=%s\n", p.PublicKey.Hex())
		if p.HasPresharedKey {
			fmt.Fprintf(&b, "preshared_key=%s\n", p.PresharedKey.Hex())
		}
		addr, err := netip.ParseAddr(p.EndpointHost)
		if err != nil {
			if resolve == nil {
				return "", fmt.Errorf("Endpoint-Host %q müsste aufgelöst werden", p.EndpointHost)
			}
			addr, err = resolve(p.EndpointHost)
			if err != nil {
				return "", fmt.Errorf("Endpoint %q nicht auflösbar: %v", p.EndpointHost, err)
			}
		}
		fmt.Fprintf(&b, "endpoint=%s\n", netip.AddrPortFrom(addr.Unmap(), p.EndpointPort))
		fmt.Fprintf(&b, "persistent_keepalive_interval=%d\n", p.PersistentKeepalive)
		b.WriteString("replace_allowed_ips=true\n")
		for _, a := range p.AllowedIPs {
			fmt.Fprintf(&b, "allowed_ip=%s\n", a)
		}
	}
	return b.String(), nil
}

// MTUOrDefault returns the configured MTU or wg-quick's default of 1420.
func (c *Config) MTUOrDefault() int {
	if c.Interface.MTU > 0 {
		return c.Interface.MTU
	}
	return 1420
}
