package ghc

import "testing"

func TestParseTarget(t *testing.T) {
	cases := []struct {
		in      string
		isOrg   bool
		owner   string
		repo    string
		wantErr bool
	}{
		{"my-org", true, "my-org", "", false},
		{"owner/repo", false, "owner", "repo", false},
		{"https://github.com/Verjson", true, "Verjson", "", false},
		{"https://github.com/you/repo", false, "you", "repo", false},
		{"http://github.com/you/repo/", false, "you", "repo", false},
		{"", false, "", "", true},
		{"a/b/c", false, "", "", true},
	}
	for _, c := range cases {
		got, err := ParseTarget(c.in)
		if c.wantErr {
			if err == nil {
				t.Errorf("ParseTarget(%q): expected error", c.in)
			}
			continue
		}
		if err != nil {
			t.Errorf("ParseTarget(%q): unexpected error %v", c.in, err)
			continue
		}
		if got.IsOrg != c.isOrg || got.Owner != c.owner || got.Repo != c.repo {
			t.Errorf("ParseTarget(%q) = %+v, want org=%v owner=%q repo=%q", c.in, got, c.isOrg, c.owner, c.repo)
		}
	}
}

func TestTargetURLAndPath(t *testing.T) {
	org := Target{IsOrg: true, Owner: "acme"}
	if org.URL() != "https://github.com/acme" {
		t.Errorf("org URL = %q", org.URL())
	}
	if org.apiPath() != "/orgs/acme/actions/runners/registration-token" {
		t.Errorf("org apiPath = %q", org.apiPath())
	}
	repo := Target{Owner: "you", Repo: "proj"}
	if repo.URL() != "https://github.com/you/proj" {
		t.Errorf("repo URL = %q", repo.URL())
	}
	if repo.apiPath() != "/repos/you/proj/actions/runners/registration-token" {
		t.Errorf("repo apiPath = %q", repo.apiPath())
	}
}
