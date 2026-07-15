package dashboard

import (
	"strings"
	"testing"

	"github.com/Verjson/github-runner-docker-compose/app/internal/dockerx"
)

func TestViewRenders(t *testing.T) {
	m := model{
		width:  120,
		height: 30,
		runners: []dockerx.Runner{
			{Name: "rust-1", Kind: "rust", State: "running", CPU: "0.10%", Mem: "80MiB / 15GiB", Job: "Idle"},
			{Name: "node-1", Kind: "node", State: "exited", CPU: "", Mem: "", Job: "Exited"},
		},
	}
	out := m.View()
	for _, want := range []string{"NAME", "KIND", "STATE", "rust-1", "node-1", "restart", "quit"} {
		if !strings.Contains(out, want) {
			t.Errorf("View() missing %q", want)
		}
	}
}

func TestViewEmpty(t *testing.T) {
	m := model{width: 80, height: 24}
	if !strings.Contains(m.View(), "No managed runners") {
		t.Errorf("empty View() should prompt to add runners")
	}
}

func TestLogsView(t *testing.T) {
	m := model{width: 80, height: 24, viewLogs: true, logsFor: "rust-1", logs: "line1\nline2\nline3"}
	out := m.View()
	if !strings.Contains(out, "logs: rust-1") || !strings.Contains(out, "line3") {
		t.Errorf("logsView() = %q", out)
	}
}
