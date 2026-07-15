// Package kinds defines the language-specific runner "kinds" the manager can build.
// Each kind maps to images/<id>.Dockerfile (built FROM gha-runner:base) and a set of
// default labels that workflows use to target it (e.g. runs-on: [self-hosted, rust]).
package kinds

// Kind is one language flavor of runner image.
type Kind struct {
	ID         string   // short id, also the image tag suffix and Dockerfile basename
	Name       string   // human-friendly name shown in the wizard
	Dockerfile string   // path (repo-root relative) to the overlay Dockerfile
	Image      string   // full image tag built for this kind
	Labels     []string // default labels attached to runners of this kind
	Blurb      string   // one-line description of what's preinstalled
}

// Base is the shared image all kinds build on top of.
var Base = Kind{
	ID:         "base",
	Name:       "Base",
	Dockerfile: "images/base.Dockerfile",
	Image:      "gha-runner:base",
	Labels:     []string{"self-hosted", "linux", "x64"},
	Blurb:      "Just the runner, no language toolchain",
}

// All is the ordered registry of selectable kinds.
var All = []Kind{
	{
		ID:         "rust",
		Name:       "Rust",
		Dockerfile: "images/rust.Dockerfile",
		Image:      "gha-runner:rust",
		Labels:     []string{"self-hosted", "linux", "x64", "rust"},
		Blurb:      "rustup, cargo, clippy, rustfmt + native build deps",
	},
	{
		ID:         "node",
		Name:       "Node",
		Dockerfile: "images/node.Dockerfile",
		Image:      "gha-runner:node",
		Labels:     []string{"self-hosted", "linux", "x64", "node"},
		Blurb:      "Node.js LTS + npm, pnpm, yarn",
	},
	{
		ID:         "python",
		Name:       "Python",
		Dockerfile: "images/python.Dockerfile",
		Image:      "gha-runner:python",
		Labels:     []string{"self-hosted", "linux", "x64", "python"},
		Blurb:      "Python 3 + pip/venv + uv",
	},
	{
		ID:         "go",
		Name:       "Go",
		Dockerfile: "images/go.Dockerfile",
		Image:      "gha-runner:go",
		Labels:     []string{"self-hosted", "linux", "x64", "go"},
		Blurb:      "Official Go toolchain",
	},
	Base,
}

// ByID returns the kind with the given id, or false if unknown.
func ByID(id string) (Kind, bool) {
	if id == Base.ID {
		return Base, true
	}
	for _, k := range All {
		if k.ID == id {
			return k, true
		}
	}
	return Kind{}, false
}
