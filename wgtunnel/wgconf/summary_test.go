package wgconf

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestSummaryHasNoKeysAndEmptyListsAreArrays(t *testing.T) {
	c, err := Parse(unifiExport)
	if err != nil {
		t.Fatal(err)
	}
	s := c.Summary()
	if s.Endpoint != "home.example.org:51820" {
		t.Errorf("endpoint %q", s.Endpoint)
	}
	if len(s.AllowedIPs) != 2 || s.AllowedIPs[0] != "0.0.0.0/0" || s.Addresses[0] != "192.168.3.2/32" || s.DNS[0] != "192.168.3.1" {
		t.Errorf("summary %+v", s)
	}
	b, _ := json.Marshal(s)
	for _, k := range []string{k1, k2, k3} {
		if strings.Contains(string(b), k) {
			t.Fatalf("summary leaks a key: %s", b)
		}
	}
	if !strings.Contains(string(b), `"warnings":[]`) {
		t.Errorf("empty warnings must encode as [], got %s", b)
	}
}
