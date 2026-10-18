package wgconf

// Summary is the non-secret part of a config: what the app shows and stores
// outside the keychain. It never contains a key.
type Summary struct {
	Endpoint   string   `json:"endpoint"`
	Addresses  []string `json:"addresses"`
	AllowedIPs []string `json:"allowedIPs"`
	DNS        []string `json:"dns"`
	Warnings   []string `json:"warnings"`
}

func (c *Config) Summary() Summary {
	s := Summary{Addresses: []string{}, AllowedIPs: []string{}, DNS: []string{}, Warnings: []string{}}
	if len(c.Peers) > 0 {
		s.Endpoint = c.Peers[0].Endpoint()
	}
	for _, a := range c.Interface.Addresses {
		s.Addresses = append(s.Addresses, a.String())
	}
	for _, p := range c.Peers {
		for _, a := range p.AllowedIPs {
			s.AllowedIPs = append(s.AllowedIPs, a.String())
		}
	}
	for _, d := range c.Interface.DNS {
		s.DNS = append(s.DNS, d.String())
	}
	s.Warnings = append(s.Warnings, c.Warnings...)
	return s
}
