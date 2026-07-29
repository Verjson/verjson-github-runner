package dockerx

import (
	"os"
	"slices"
	"strings"
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

func TestEphemeralRunUsesSupervisorAndKeepsSocketOutOfJobByDefault(t *testing.T) {
	args := runArgs(RunSpec{
		Name: "isolated-1", Image: "gha-runner:node", URL: "https://github.com/Verjson",
		Token: "token", Labels: "self-hosted,isolated", Group: "isolated", Workdir: "_work",
		Ephemeral: true,
	})
	joined := strings.Join(args, " ")
	if !slices.Contains(args, "RUNNER_IMAGE=gha-runner:node") ||
		!slices.Contains(args, "RUNNER_EPHEMERAL=1") ||
		!slices.Contains(args, "gha.mode=ephemeral-supervisor") ||
		args[len(args)-1] != "supervise" {
		t.Fatalf("ephemeral args do not launch the supervisor contract: %v", joined)
	}
	if slices.Contains(args, "RUNNER_CHILD_MOUNT_SOCK=1") {
		t.Fatalf("job child unexpectedly receives the Docker socket: %v", joined)
	}
	if strings.Contains(joined, "token") || slices.Contains(args, "GITHUB_PAT=token") {
		t.Fatalf("renewable credential appears in docker argv: %v", joined)
	}
	if !slices.Contains(args, "GITHUB_PAT_FIFO=/run/gha-secrets/github-pat") {
		t.Fatalf("one-use credential transport is not configured: %v", joined)
	}
}

func TestEphemeralRunCanExplicitlyPassSocketToTrustedJob(t *testing.T) {
	args := runArgs(RunSpec{
		Name: "trusted-docker", Image: "gha-runner:base", Ephemeral: true, MountSock: true,
	})
	if !slices.Contains(args, "RUNNER_CHILD_MOUNT_SOCK=1") {
		t.Fatalf("explicit trusted socket selection was not passed to supervisor: %v", args)
	}
}

func TestPATTransportRejectsReplay(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/github-pat"
	if err := makePATFIFO(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := deliverPAT(path, "secret"); err == nil {
		t.Fatal("delivery unexpectedly replayed after transport destruction")
	}
}
