// Package ghc wraps the GitHub CLI (`gh`) so the manager can authenticate and fetch
// runner registration data without ever asking the user to paste a PAT.
//
// The user's existing `gh auth login` session is reused: `gh auth token` yields an OAuth
// token that works as a Bearer token against the REST API. We hand that token to the
// container as GITHUB_PAT so entrypoint.sh can auto-refresh registration tokens on every
// restart (a one-shot registration token would expire after ~1h and break restarts).
package ghc

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// ErrNotInstalled is returned when the `gh` binary is not on PATH.
var ErrNotInstalled = errors.New("gh (GitHub CLI) is not installed")

// ErrNotAuthed is returned when `gh` is installed but the user is not logged in.
var ErrNotAuthed = errors.New("gh is not authenticated (run: gh auth login)")

// Target identifies where runners register: either a whole org or a single repo.
type Target struct {
	IsOrg bool
	Owner string // org name, or repo owner
	Repo  string // empty for org targets
}

// URL returns the github.com URL to register the runner against.
func (t Target) URL() string {
	if t.IsOrg {
		return "https://github.com/" + t.Owner
	}
	return "https://github.com/" + t.Owner + "/" + t.Repo
}

// Slug is a short human label, e.g. "my-org" or "owner/repo".
func (t Target) Slug() string {
	if t.IsOrg {
		return t.Owner
	}
	return t.Owner + "/" + t.Repo
}

// apiPath is the registration-token endpoint for this target.
func (t Target) apiPath() string {
	if t.IsOrg {
		return fmt.Sprintf("/orgs/%s/actions/runners/registration-token", t.Owner)
	}
	return fmt.Sprintf("/repos/%s/%s/actions/runners/registration-token", t.Owner, t.Repo)
}

func run(args ...string) (string, error) {
	out, err := exec.Command("gh", args...).CombinedOutput()
	if err != nil {
		if _, lookErr := exec.LookPath("gh"); lookErr != nil {
			return "", ErrNotInstalled
		}
		return "", fmt.Errorf("gh %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return strings.TrimSpace(string(out)), nil
}

// EnsureReady verifies gh is installed and authenticated, returning the logged-in login.
func EnsureReady() (login string, err error) {
	if _, err := exec.LookPath("gh"); err != nil {
		return "", ErrNotInstalled
	}
	if err := exec.Command("gh", "auth", "status").Run(); err != nil {
		return "", ErrNotAuthed
	}
	return CurrentLogin()
}

// CurrentLogin returns the authenticated user's login name.
func CurrentLogin() (string, error) {
	return run("api", "-q", ".login", "/user")
}

// IsInstalled reports whether the gh binary is on PATH.
func IsInstalled() bool {
	_, err := exec.LookPath("gh")
	return err == nil
}

// Login runs `gh auth login` interactively, inheriting the terminal so the user can
// complete the browser/device flow. Returns once gh has stored credentials.
func Login() error {
	cmd := exec.Command("gh", "auth", "login")
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

// Token returns the OAuth token for the active gh session.
func Token() (string, error) {
	return run("auth", "token")
}

// Repo is a lightweight repo listing entry.
type Repo struct {
	NameWithOwner string `json:"nameWithOwner"`
}

// ListRepos returns repos the user can administer (admin permission), newest first.
func ListRepos(limit int) ([]string, error) {
	out, err := run("repo", "list", "--no-archived", "--limit", fmt.Sprint(limit),
		"--json", "nameWithOwner,viewerPermission", "-q",
		`[.[] | select(.viewerPermission=="ADMIN") | .nameWithOwner] | .[]`)
	if err != nil {
		return nil, err
	}
	return nonEmptyLines(out), nil
}

// ListOrgs returns the orgs the user belongs to.
func ListOrgs() ([]string, error) {
	out, err := run("api", "-q", ".[].login", "/user/orgs")
	if err != nil {
		return nil, err
	}
	return nonEmptyLines(out), nil
}

// ParseTarget turns "owner/repo", "org", or a github.com URL into a Target.
func ParseTarget(s string) (Target, error) {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "https://github.com/")
	s = strings.TrimPrefix(s, "http://github.com/")
	s = strings.Trim(s, "/")
	if s == "" {
		return Target{}, errors.New("empty target")
	}
	parts := strings.Split(s, "/")
	switch len(parts) {
	case 1:
		return Target{IsOrg: true, Owner: parts[0]}, nil
	case 2:
		return Target{Owner: parts[0], Repo: parts[1]}, nil
	default:
		return Target{}, fmt.Errorf("cannot parse target %q (want owner, owner/repo, or a github.com URL)", s)
	}
}

// tokenResponse is the shape returned by the registration-token endpoint.
type tokenResponse struct {
	Token string `json:"token"`
}

// Preflight fetches a registration token to prove the current gh session has the
// scope/admin rights needed for this target. The token itself is discarded — the
// container fetches its own fresh one at start via the passed-in gh OAuth token.
func Preflight(t Target) error {
	out, err := run("api", "--method", "POST", "-H", "Accept: application/vnd.github+json", t.apiPath())
	if err != nil {
		return scopeHint(t, err)
	}
	var tr tokenResponse
	if json.Unmarshal([]byte(out), &tr) != nil || tr.Token == "" {
		return fmt.Errorf("unexpected response from %s", t.apiPath())
	}
	return nil
}

// scopeHint enriches a 403/404 with the concrete fix.
func scopeHint(t Target, err error) error {
	msg := err.Error()
	if strings.Contains(msg, "403") || strings.Contains(msg, "Must have admin") || strings.Contains(msg, "404") {
		if t.IsOrg {
			return fmt.Errorf("%w\n  Org runners need the 'admin:org' scope and org-admin rights.\n  Grant it with:  gh auth refresh -s admin:org", err)
		}
		return fmt.Errorf("%w\n  Repo runners need the 'repo' scope and admin on %s.\n  Grant it with:  gh auth refresh -s repo", err, t.Slug())
	}
	return err
}

// RefreshScope runs `gh auth refresh -s <scope>` interactively (opens a browser flow).
func RefreshScope(scope string) error {
	cmd := exec.Command("gh", "auth", "refresh", "-s", scope)
	return cmd.Run()
}

func nonEmptyLines(s string) []string {
	var out []string
	for _, l := range strings.Split(s, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out
}
