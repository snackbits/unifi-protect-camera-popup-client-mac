package wgconf

import (
	"errors"
	"fmt"
	"net/netip"
	"strings"
	"testing"
)

const (
	k1 = "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=" // example keys from wg(8)
	k2 = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
	k3 = "TrMvSoP4jYQlY6RIzBgbssQqY3vxI2Pi+y71lOWWXX0="
)

// Shape of a UniFi gateway export (Settings > VPN > WireGuard > Download).
var unifiExport = "[Interface]\r\n" +
	"PrivateKey = " + k1 + "\r\n" +
	"Address = 192.168.3.2/32\r\n" +
	"DNS = 192.168.3.1\r\n" +
	"\r\n" +
	"[Peer]\r\n" +
	"PublicKey = " + k2 + "\r\n" +
	"PresharedKey = " + k3 + "\r\n" +
	"AllowedIPs = 0.0.0.0/0, ::/0\r\n" +
	"Endpoint = home.example.org:51820\r\n" +
	"PersistentKeepalive = 25\r\n"

func TestUniFiExport(t *testing.T) {
	c, err := Parse(unifiExport)
	if err != nil {
		t.Fatal(err)
	}
	if c.Interface.PrivateKey.Base64() != k1 {
		t.Error("private key")
	}
	if got := c.Interface.Addresses; len(got) != 1 || got[0] != netip.MustParsePrefix("192.168.3.2/32") {
		t.Errorf("address %v", got)
	}
	if len(c.Interface.DNS) != 1 || c.Interface.DNS[0].String() != "192.168.3.1" {
		t.Errorf("dns %v", c.Interface.DNS)
	}
	if c.MTUOrDefault() != 1420 {
		t.Error("default mtu")
	}
	p := c.Peers[0]
	if p.PublicKey.Base64() != k2 || !p.HasPresharedKey || p.PresharedKey.Base64() != k3 {
		t.Error("peer keys")
	}
	if len(p.AllowedIPs) != 2 || p.AllowedIPs[1].String() != "::/0" {
		t.Errorf("allowed %v", p.AllowedIPs)
	}
	if p.EndpointHost != "home.example.org" || p.EndpointPort != 51820 || p.PersistentKeepalive != 25 {
		t.Errorf("endpoint/keepalive %+v", p)
	}
}

func TestOptionalFieldsAndVariants(t *testing.T) {
	txt := "\ufeff# exported\n[interface]\nprivatekey=" + k1 + "\n" +
		"Address = 10.0.0.2, fd00::2/128 # inline comment\nAddress = 10.0.0.3/24\n" +
		"DNS = 10.0.0.1, lan.local\nMTU = 1280\nPostUp = echo hi\n" +
		"[Peer]\nPublicKey=" + k2 + "\nAllowedIPs = 10.0.0.0/24\nAllowedIPs=192.168.1.7/24\n" +
		"Endpoint = [2001:db8::1]:51820\nPersistentKeepalive = off\n"
	c, err := Parse(txt)
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Interface.Addresses) != 3 || c.Interface.Addresses[0].String() != "10.0.0.2/32" ||
		c.Interface.Addresses[2].String() != "10.0.0.3/24" {
		t.Errorf("addresses %v", c.Interface.Addresses)
	}
	if len(c.Interface.DNSSearch) != 1 || c.Interface.DNSSearch[0] != "lan.local" {
		t.Errorf("search %v", c.Interface.DNSSearch)
	}
	if c.MTUOrDefault() != 1280 {
		t.Error("mtu")
	}
	if len(c.Warnings) != 1 {
		t.Errorf("warnings %v", c.Warnings)
	}
	p := c.Peers[0]
	if p.HasPresharedKey || p.PersistentKeepalive != 0 {
		t.Error("psk/keepalive")
	}
	if p.AllowedIPs[1].String() != "192.168.1.0/24" { // masked like wg(8)
		t.Errorf("allowed %v", p.AllowedIPs)
	}
	if p.EndpointHost != "2001:db8::1" || p.Endpoint() != "[2001:db8::1]:51820" {
		t.Errorf("endpoint %q", p.Endpoint())
	}
}

func TestUAPI(t *testing.T) {
	c, err := Parse(unifiExport)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c.UAPI(nil); err == nil {
		t.Error("hostname without resolver must fail")
	}
	u, err := c.UAPI(func(string) (netip.Addr, error) { return netip.MustParseAddr("203.0.113.5"), nil })
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"private_key=c809f3e5317e9575c9b5ed78b638b7ce530dabe85ddab614220241801ddf0669\n",
		"endpoint=203.0.113.5:51820\n", "persistent_keepalive_interval=25\n",
		"allowed_ip=0.0.0.0/0\n", "allowed_ip=::/0\n", "preshared_key=",
	} {
		if !strings.Contains(u, want) {
			t.Errorf("UAPI missing %q:\n%s", want, u)
		}
	}
}

func TestErrors(t *testing.T) {
	iface := "[Interface]\nPrivateKey = " + k1 + "\nAddress = 10.0.0.2/32\n"
	peer := "[Peer]\nPublicKey = " + k2 + "\nAllowedIPs = 10.0.0.0/24\nEndpoint = 1.2.3.4:51820\n"
	cases := []struct {
		name, txt, want string
		line            int
	}{
		{"empty", "", "[Interface]-Abschnitt fehlt", 0},
		{"no peer", iface, "kein [Peer]", 0},
		{"no privkey", "[Interface]\nAddress=10.0.0.2\n" + peer, "PrivateKey fehlt", 0},
		{"no address", "[Interface]\nPrivateKey=" + k1 + "\n" + peer, "Address fehlt", 0},
		{"bad base64", strings.Replace(iface, k1, "not-base64!!", 1) + peer, "Base64", 2},
		{"short key", strings.Replace(iface, k1, "AAAA", 1) + peer, "3 statt 32", 2},
		{"bad address", strings.Replace(iface, "10.0.0.2/32", "10.0.0.300/32", 1) + peer, "Address", 3},
		{"bad mtu", iface + "MTU = 99999\n" + peer, "MTU", 4},
		{"unknown iface key", iface + "Foo = bar\n" + peer, "unbekannter Schlüssel", 4},
		{"unknown section", iface + "[Peers]\n", "unbekannter Abschnitt", 4},
		{"unclosed section", "[Interface\n", "nicht geschlossen", 1},
		{"no equals", iface + "PrivateKey\n", "Schlüssel = Wert", 4},
		{"before section", "PrivateKey = " + k1 + "\n", "vor dem ersten Abschnitt", 1},
		{"dup interface", iface + iface + peer, "mehrfach", 4},
		{"dup key", iface + "PrivateKey = " + k1 + "\n" + peer, "doppelt (zuerst in Zeile 2)", 4},
		{"peer no pubkey", iface + "[Peer]\nAllowedIPs=10.0.0.0/24\nEndpoint=1.2.3.4:1\n", "PublicKey fehlt", 4},
		{"peer no allowed", iface + "[Peer]\nPublicKey=" + k2 + "\nEndpoint=1.2.3.4:1\n", "AllowedIPs fehlt", 4},
		{"peer no endpoint", iface + "[Peer]\nPublicKey=" + k2 + "\nAllowedIPs=10.0.0.0/24\n", "Endpoint fehlt", 4},
		{"endpoint no port", strings.Replace(iface+peer, "1.2.3.4:51820", "1.2.3.4", 1), "host:port", 7},
		{"endpoint bad port", strings.Replace(iface+peer, "1.2.3.4:51820", "1.2.3.4:70000", 1), "Port", 7},
		{"endpoint v6 no brackets", strings.Replace(iface+peer, "1.2.3.4:51820", "2001:db8::1:51820", 1), "host:port", 7},
		{"bad allowed", strings.Replace(iface+peer, "10.0.0.0/24", "10.0.0.0/33", 1), "AllowedIPs", 6},
		{"bad keepalive", iface + peer + "PersistentKeepalive = -1\n", "PersistentKeepalive", 8},
		{"dup peer", iface + peer + peer, "PublicKey doppelt", 8},
		{"bad psk", iface + peer + "PresharedKey = xyz\n", "PresharedKey", 8},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse(tc.txt)
			if err == nil {
				t.Fatalf("expected error containing %q", tc.want)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("got %q, want substring %q", err, tc.want)
			}
			var pe *ParseError
			if !errors.As(err, &pe) || pe.Line != tc.line {
				t.Errorf("line: got %v, want %d", pe, tc.line)
			}
		})
	}
}

func TestKeyFormattingIsRedacted(t *testing.T) {
	c, err := Parse(unifiExport)
	if err != nil {
		t.Fatal(err)
	}
	secrets := []string{k1, k2, k3,
		c.Interface.PrivateKey.Hex(), c.Peers[0].PublicKey.Hex(), c.Peers[0].PresharedKey.Hex()}
	k := c.Interface.PrivateKey
	for _, out := range []string{
		fmt.Sprintf("%+v", c), fmt.Sprintf("%v", c), fmt.Sprintf("%#v", c),
		fmt.Sprintf("%+v", *c), fmt.Sprintf("%#v", *c), fmt.Sprintf("%+v", c.Peers),
		fmt.Sprintf("%v", k), fmt.Sprintf("%s", k), fmt.Sprintf("%x", k), fmt.Sprintf("%#v", k),
	} {
		for _, s := range secrets {
			if strings.Contains(out, s) {
				t.Fatal("formatted config contains key material") // never print out: it holds the key
			}
		}
	}
	if got := fmt.Sprintf("%+v", k); got != "<redacted>" {
		t.Fatalf("key formats as %d bytes, want <redacted>", len(got))
	}
}
