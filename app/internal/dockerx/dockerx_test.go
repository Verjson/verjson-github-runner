package dockerx

import "testing"

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
