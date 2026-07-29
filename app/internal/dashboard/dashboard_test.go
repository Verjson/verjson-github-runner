package dashboard

import (
	"errors"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"

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
	out := m.View().Content
	for _, want := range []string{"NAME", "KIND", "STATE", "rust-1", "node-1", "restart", "quit"} {
		if !strings.Contains(out, want) {
			t.Errorf("View() missing %q", want)
		}
	}
}

func TestViewEmpty(t *testing.T) {
	m := model{width: 80, height: 24}
	if !strings.Contains(m.View().Content, "No managed runners") {
		t.Errorf("empty View() should prompt to add runners")
	}
}

func TestViewUsesAltScreen(t *testing.T) {
	// The dashboard must own the whole screen and restore the user's terminal on quit.
	// Bubble Tea v2 moved this from a program option to a per-view flag, so assert it here.
	for _, m := range []model{{width: 80, height: 24}, {width: 80, height: 24, viewLogs: true}} {
		if !m.View().AltScreen {
			t.Errorf("View() with viewLogs=%v should render on the alt screen", m.viewLogs)
		}
	}
}

func TestLogsView(t *testing.T) {
	m := model{width: 80, height: 24, viewLogs: true, logsFor: "rust-1", logs: "line1\nline2\nline3"}
	out := m.View().Content
	if !strings.Contains(out, "logs: rust-1") || !strings.Contains(out, "line3") {
		t.Errorf("logsView() = %q", out)
	}
}

func TestRestartReportsRelaunchInstructionsWhenUnavailable(t *testing.T) {
	original := restartRunner
	restartRunner = func(string) error { return errors.New("fresh PAT required") }
	t.Cleanup(func() { restartRunner = original })

	m := model{runners: []dockerx.Runner{{Name: "rust-1"}}}
	updated, cmd := m.handleKey(tea.KeyPressMsg{Code: 'r', Text: "r"})
	updated, _ = updated.(model).Update(cmd())
	status := updated.(model).status

	for _, want := range []string{"restart unavailable", "fresh PAT required", "relaunch via setup"} {
		if !strings.Contains(status, want) {
			t.Errorf("restart failure status %q missing %q", status, want)
		}
	}
}

func TestRestartRefreshesRunnersOnSuccess(t *testing.T) {
	originalRestart := restartRunner
	originalSnapshot := snapshotRunner
	restartRunner = func(string) error { return nil }
	snapshotRunner = func() ([]dockerx.Runner, error) {
		return []dockerx.Runner{{Name: "rust-1", State: "running"}}, nil
	}
	t.Cleanup(func() {
		restartRunner = originalRestart
		snapshotRunner = originalSnapshot
	})

	msg := restart("rust-1")()

	runners, ok := msg.(dataMsg)
	if !ok {
		t.Fatalf("restart success returned %T, want dataMsg refresh", msg)
	}
	if len(runners) != 1 || runners[0].State != "running" {
		t.Fatalf("restart success refresh = %#v, want refreshed runner", runners)
	}
}
