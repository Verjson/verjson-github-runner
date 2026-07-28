package dockerx

import (
	"slices"
	"testing"
)

func TestParseJob(t *testing.T) {
	cases := []struct {
		state string
		logs  string
		want  string
	}{
		{"exited", "", "Exited"},
		{"running", "√ Connected to GitHub\nListening for Jobs", "Idle"},
		{"running", "Listening for Jobs\nRunning job: build-and-test", "▶ build-and-test"},
		{"running", "Running job: x\nJob build completed with result: Succeeded", "Idle"},
		{"running", "√ Authentication\nRegistering runner", "Registering…"},
		{"running", "some unrelated line", "Starting…"},
	}
	for _, c := range cases {
		if got := parseJob(c.state, c.logs); got != c.want {
			t.Errorf("parseJob(%q, ...) = %q, want %q", c.state, got, c.want)
		}
	}
}

func TestKindFromImage(t *testing.T) {
	if kindFromImage("gha-runner:rust") != "rust" {
		t.Errorf("kindFromImage rust failed")
	}
	if kindFromImage("plain") != "plain" {
		t.Errorf("kindFromImage no-colon failed")
	}
}

func TestContainerName(t *testing.T) {
	s := RunSpec{Name: "rust-1"}
	if s.Container() != "gha-rust-1" {
		t.Errorf("Container() = %q", s.Container())
	}
}

func TestRunArgsUseDisposableContainerForEphemeralRunner(t *testing.T) {
	args := runArgs(RunSpec{
		Name:      "pr-1",
		Image:     "gha-runner:base",
		URL:       "https://github.com/Verjson",
		Token:     "token",
		Labels:    "self-hosted,ephemeral",
		Group:     "untrusted-pr",
		Workdir:   "_work",
		Ephemeral: true,
	})

	if !slices.Contains(args, "--rm") {
		t.Fatalf("ephemeral docker args must remove the container: %v", args)
	}
	if slices.Contains(args, "--restart") || slices.Contains(args, "unless-stopped") {
		t.Fatalf("ephemeral docker args must not install a restart policy: %v", args)
	}
	if !containsAdjacent(args, "-e", "RUNNER_EPHEMERAL=1") {
		t.Fatalf("ephemeral docker args must explicitly enable runner ephemeral mode: %v", args)
	}
	if !containsAdjacent(args, "--label", "gha.ephemeral=true") {
		t.Fatalf("ephemeral docker args must label the lifecycle boundary: %v", args)
	}
}

func TestRunArgsPreserveRestartingPersistentRunner(t *testing.T) {
	args := runArgs(RunSpec{
		Name:    "ci-1",
		Image:   "gha-runner:base",
		URL:     "https://github.com/Verjson",
		Token:   "token",
		Labels:  "self-hosted,ci",
		Group:   "trusted-ci",
		Workdir: "_work",
	})

	if slices.Contains(args, "--rm") {
		t.Fatalf("persistent docker args must preserve the writable layer: %v", args)
	}
	if !containsAdjacent(args, "--restart", "unless-stopped") {
		t.Fatalf("persistent docker args must retain restart behavior: %v", args)
	}
	if slices.Contains(args, "RUNNER_EPHEMERAL=1") {
		t.Fatalf("persistent docker args must not enable ephemeral registration: %v", args)
	}
	if !containsAdjacent(args, "--label", "gha.ephemeral=false") {
		t.Fatalf("persistent docker args must label the lifecycle boundary: %v", args)
	}
}

func containsAdjacent(values []string, first, second string) bool {
	for i := 0; i+1 < len(values); i++ {
		if values[i] == first && values[i+1] == second {
			return true
		}
	}
	return false
}
