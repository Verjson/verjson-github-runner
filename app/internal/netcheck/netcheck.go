// Package netcheck verifies the machine can reach GitHub over outbound HTTPS (443),
// which is the ONLY connectivity a self-hosted runner needs. It respects any configured
// HTTP(S) proxy (via the standard *_PROXY env vars) so the result matches what the runner
// containers will actually experience.
package netcheck

import (
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
)

var (
	okStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#04B575"))
	failStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5F87")).Bold(true)
	dimStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	titleSty  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#7D56F4"))
)

// Hosts the runner must reach over 443. We probe with a TLS handshake (not an HTTP request):
// some of these — e.g. the objects.* blob store — never answer a bare HEAD/GET to "/", so a
// completed TLS handshake is the honest signal that outbound 443 to the host works.
var Hosts = []string{
	"api.github.com",
	"github.com",
	"codeload.github.com",
	"objects.githubusercontent.com",
}

// proxyHosts are used when a proxy is configured (we must go through it via HTTP CONNECT,
// so we probe with HTTP HEAD); limited to hosts that reliably answer at "/".
var proxyHosts = []string{
	"https://api.github.com",
	"https://github.com",
	"https://codeload.github.com",
}

// Result is the outcome of probing one endpoint.
type Result struct {
	Endpoint string
	OK       bool
	Detail   string // status/detail on success, error on failure
}

// ProxyURL returns the effective outbound proxy from the environment, if any.
func ProxyURL() string {
	for _, k := range []string{"HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"} {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	return ""
}

// Check probes GitHub over 443. With no proxy it dials TLS directly (most accurate); with a
// proxy configured it issues HTTP HEADs so the traffic actually traverses the proxy.
func Check() []Result {
	if ProxyURL() != "" {
		return checkViaProxy()
	}
	return checkDirect()
}

// checkDirect completes a TLS handshake to each host:443.
func checkDirect() []Result {
	results := make([]Result, 0, len(Hosts))
	for _, h := range Hosts {
		conn, err := tls.DialWithDialer(
			&net.Dialer{Timeout: 6 * time.Second}, "tcp", h+":443",
			&tls.Config{ServerName: h})
		if err != nil {
			results = append(results, Result{Endpoint: h, OK: false, Detail: shortErr(err)})
			continue
		}
		_ = conn.Close()
		results = append(results, Result{Endpoint: h, OK: true, Detail: "TLS 443 ok"})
	}
	return results
}

// checkViaProxy issues HTTP HEADs through the configured proxy.
func checkViaProxy() []Result {
	tr := &http.Transport{
		Proxy:               http.ProxyFromEnvironment,
		DialContext:         (&net.Dialer{Timeout: 6 * time.Second}).DialContext,
		TLSHandshakeTimeout: 6 * time.Second,
	}
	client := &http.Client{Transport: tr, Timeout: 10 * time.Second}
	results := make([]Result, 0, len(proxyHosts))
	for _, e := range proxyHosts {
		req, _ := http.NewRequest(http.MethodHead, e, nil)
		resp, err := client.Do(req)
		if err != nil {
			results = append(results, Result{Endpoint: e, OK: false, Detail: shortErr(err)})
			continue
		}
		resp.Body.Close()
		results = append(results, Result{Endpoint: e, OK: true, Detail: resp.Status})
	}
	return results
}

// AllOK reports whether every probe succeeded.
func AllOK(results []Result) bool {
	for _, r := range results {
		if !r.OK {
			return false
		}
	}
	return true
}

// Print renders a human-friendly report and returns whether everything passed.
func Print() bool {
	fmt.Println(titleSty.Render("Network preflight"))
	if p := ProxyURL(); p != "" {
		fmt.Println(dimStyle.Render("  via proxy: " + p))
	}
	results := Check()
	for _, r := range results {
		if r.OK {
			fmt.Printf("  %s %-40s %s\n", okStyle.Render("✓"), r.Endpoint, dimStyle.Render(r.Detail))
		} else {
			fmt.Printf("  %s %-40s %s\n", failStyle.Render("✗"), r.Endpoint, dimStyle.Render(r.Detail))
		}
	}
	ok := AllOK(results)
	fmt.Println()
	if ok {
		fmt.Println(okStyle.Render("  Outbound 443 to GitHub is open — the runner will connect fine."))
	} else {
		fmt.Println(failStyle.Render("  Some endpoints are unreachable.") +
			dimStyle.Render("  Allow outbound 443 to the hosts above, or set HTTPS_PROXY."))
	}
	// Inbound is intentionally not tested: self-hosted runners open an OUTBOUND long-poll
	// to GitHub and receive jobs over it. No inbound ports, port-forwarding, or static IP
	// are required — so there is nothing meaningful to probe on the inbound side.
	fmt.Println(dimStyle.Render("  Inbound: not required. Runners poll GitHub outbound; no open ports / static IP needed."))
	return ok
}

func shortErr(err error) string {
	s := err.Error()
	// Trim the noisy `Head "https://…":` prefix the http client adds.
	if i := strings.LastIndex(s, ": "); i >= 0 && strings.Contains(s, "\"") {
		s = s[i+2:]
	}
	return s
}
