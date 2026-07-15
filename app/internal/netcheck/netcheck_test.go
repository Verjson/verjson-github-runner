package netcheck

import (
	"os"
	"testing"
)

func TestAllOK(t *testing.T) {
	if !AllOK([]Result{{OK: true}, {OK: true}}) {
		t.Error("AllOK should be true when every result passed")
	}
	if AllOK([]Result{{OK: true}, {OK: false}}) {
		t.Error("AllOK should be false when any result failed")
	}
}

func TestProxyURL(t *testing.T) {
	// Save and clear all proxy vars so the test is deterministic.
	keys := []string{"HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"}
	saved := map[string]string{}
	for _, k := range keys {
		saved[k] = os.Getenv(k)
		os.Unsetenv(k)
	}
	defer func() {
		for k, v := range saved {
			if v != "" {
				os.Setenv(k, v)
			}
		}
	}()

	if ProxyURL() != "" {
		t.Errorf("ProxyURL should be empty with no proxy env set, got %q", ProxyURL())
	}
	os.Setenv("HTTPS_PROXY", "http://proxy.internal:3128")
	if ProxyURL() != "http://proxy.internal:3128" {
		t.Errorf("ProxyURL = %q, want the HTTPS_PROXY value", ProxyURL())
	}
}
