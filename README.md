# Dockerized GitHub Actions self-hosted runner

Runs a self-hosted runner in Docker. Works on any machine (home PC, VPS, mini PC)
**behind NAT / with a dynamic IP** — the runner only makes *outbound* HTTPS
connections to GitHub, so no static IP and no port-forwarding are needed.

## Cross-platform

The runner runs **inside a Linux container**, so the *same* setup works on
**Windows, macOS, and Linux** — only the launcher script differs:

| OS | Prerequisite | Launcher |
|----|--------------|----------|
| **Linux** | Docker Engine | `./setup.sh` |
| **macOS** (Intel & Apple Silicon) | [Docker Desktop](https://www.docker.com/products/docker-desktop/) | `./setup.sh` |
| **Windows 10/11** | [Docker Desktop](https://www.docker.com/products/docker-desktop/) (WSL2 backend) | `./setup.ps1` |

The image is **multi-arch** (`amd64` + `arm64`), so it builds and runs natively on
Apple Silicon Macs and ARM Linux — no emulation.

> On Windows, if scripts are blocked, run once:
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` then `./setup.ps1`.

## Published images (GHCR) — build once in CI, pull everywhere

This repo is the **single source of truth** for the runner image used by Verjson and
Tequity. CI builds one shared artifact and pushes it to
**`ghcr.io/verjson/gha-runner`** (public, so hosts pull with no credentials):

| Tag | Contents |
|-----|----------|
| `:base`, `:latest` | base runner (`gh`, Docker CLI + buildx + compose, Node.js 24/npm, non-root) |
| `:rust` `:node` `:python` `:go` | base + that language toolchain |
| `:base-<version>` (e.g. `:base-v0.1.0`) | pinned release, `FROM` a tagged release |
| `:base-<sha>`, `:<kind>-<sha>` | commit-addressed tag — resolve its receipt and pin the digest downstream |

- **Multi-arch:** published tags are `amd64` + `arm64`.
- The **base image ships `gh`, Node.js 24/npm, and Docker CLI + buildx + compose plugins**, so
  `[self-hosted, docker]` jobs can run `docker build --secret` (BuildKit) and
  `docker compose` against a mounted host socket.
- Every published image includes BuildKit SBOM and provenance attestations. Each publish
  run also retains a receipt mapping every commit-addressed `:*-<sha>` tag to its immutable
  manifest digest.

**Two ways to consume the same image:**

1. **Your own host** (home PC / VPS / mini PC) — the `gha` manager or `setup.sh`
   below. These build locally today; you can also just `docker pull` a published tag.
2. **Cloud hosts, via the CLI** —
   `verjson cloud runner <lane> --runner-image ghcr.io/verjson/gha-runner@sha256:<manifest-digest> --runner-group <dedicated-group>`
   deploys the exact attested manifest with the host socket mounted. Container mode
   requires an existing, explicitly named non-`Default` runner group with public
   repositories disabled and access restricted to selected trusted private
   repositories and workflows; the CLI does not create or widen that access.
   - **GCP** uses self-healing Spot MIG VMs and one-job ephemeral containers. Each
     container start mints a fresh registration token from the host's GitHub App
     integration.
   - **DigitalOcean** uses stable, non-ephemeral runner registrations on named
     Droplets. The configured runner identity survives container and host restarts;
     its initial one-shot registration token is delivered over the reviewed SSH
     standard-input channel and is not persisted.
   See [`verjson-cli-cloud#88`](https://github.com/Verjson/verjson-cli-cloud/issues/88).

Host provisioning (your box, GCP, or DigitalOcean) is decoupled from the runner
artifact (this image), so every path can stay in lockstep on one runner definition.

### The `ci` runner contract

The exact `ci` label (matched case-insensitively, like GitHub labels) declares a portable
capability contract shared by Verjson and Tequity. Before minting a registration token
or running `config.sh`, the container
exercises `gh`, Docker daemon access, Compose, Buildx, Node.js 24, npm, jq, git, bash,
curl, grep, sed, awk, find, base64, tar, and gzip. If any check fails, startup stops and
the runner never becomes schedulable. Labels such as `circleci` or `ci-extra` do not opt
into this contract. PowerShell is not part of the portable Linux contract.

Deploy immutable digests rather than mutable tags:

```sh
docker pull ghcr.io/verjson/gha-runner@sha256:<manifest-digest>
```

Run the same admission without registration credentials before provisioning:

```sh
RUNNER_IMAGE=ghcr.io/verjson/gha-runner@sha256:<manifest-digest>
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
docker run --rm \
  --group-add "$DOCKER_GID" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$RUNNER_IMAGE" ci
```

The standalone `ci` command exercises the complete capability matrix and exits
without reading `GITHUB_URL`, resolving a token, or running `config.sh`.

Attaching `ci` to an organization runner remains a rollout action. Use the digest receipt
from the publish workflow, verify admission on the target host, and preserve the existing
runner-group repository allowlist.

## The `gha` manager — TUI (recommended)

`gha` is a small terminal app that provisions and monitors **many** runners at once.
It reuses your **GitHub CLI** login, so there's **no PAT to paste** — it fetches
registration tokens for you. You pick how many runners you want and **which languages**,
and it builds the right toolchain images and launches everything.

### Prerequisites
- **Docker** (Engine or Desktop) running
- **[GitHub CLI](https://cli.github.com)** installed and logged in: `gh auth login`
- **Go 1.22+** (only to build the binary once)

### Fastest path — one command (Linux · macOS · Windows/WSL2)

Don't even need to clone first — this fetches the repo and sets everything up:
```bash
curl -fsSL https://raw.githubusercontent.com/Verjson/verjson-github-runner/main/install.sh | bash
```
It clones into `~/github-runner` (override with `GHA_DIR=…`), then runs `bootstrap.sh`.
Set up without launching:
```bash
curl -fsSL https://raw.githubusercontent.com/Verjson/verjson-github-runner/main/install.sh | bash -s -- --no-run
```

Already cloned? Just run:
```bash
./bootstrap.sh
```
It installs anything missing (**Docker**, **GitHub CLI**), builds the `gha` binary
(using a `golang` container if you don't have Go), then launches `gha up`. **Go is not
required on the host.** Use `./bootstrap.sh --no-run` to set up without launching.

- **Linux** — apt/dnf/yum/pacman/apk supported; Docker via the official convenience script.
- **macOS** — installs Docker Desktop + `gh` via Homebrew (start Docker Desktop once, re-run).
- **Windows** — run it inside **WSL2** (Ubuntu). Docker Desktop's WSL2 backend runs the
  Linux runner containers; the script is just the Linux path there.

> On a fresh Linux box you may need to log out/in once so your user joins the `docker`
> group — the script activates it for the current session automatically where possible.

### Or build & run manually
```bash
./build.sh          # compiles ./gha  (or: cd app && go build -o ../gha .)
./gha up            # ⭐ one command: gh login (if needed) → network check → add runners
./gha               # or an interactive menu: add / dashboard / list / net check
```

### `gha up` — the one-command path
`gha up` walks the whole thing end to end:
1. checks Docker is running,
2. runs **`gh auth login`** for you if you're not already signed in,
3. runs a **network preflight** — confirms outbound **443** to GitHub is open
   (and reminds you inbound/static-IP aren't needed), then
4. drops into the add-runners wizard (target → kinds → counts → options).

### What each command does
1. **`gha doctor`** — verifies Docker + `gh` are ready.
2. **`gha netcheck`** — tests outbound 443 to GitHub (honors `HTTPS_PROXY`). Alias: `net`.
3. **`gha add`** — a guided wizard:
   - pick a **repo you administer** or an **org** (from a list, or type `owner/repo`),
   - choose **which kinds** of runners (multi-select), and
   - **how many of each** (e.g. 2 × Rust, 3 × Node) — all on one screen,
   - set labels/group/ephemeral, confirm, and it builds + launches the containers.
   - If your `gh` session lacks the scope (e.g. `admin:org`), it offers to run
     `gh auth refresh` for you.
4. **`gha dashboard`** — a **btop-style live monitor** (aliases: `dash`, `top`): per-runner
   state, CPU/mem, and current job, with keys to **restart / stop / view logs**.

```
  ↑/↓ move · l logs · r restart · s stop · q quit
```

### Runner "kinds" (preloaded toolchains)

Each kind is a thin image built on the base runner, with default labels so workflows can
target it via `runs-on`:

| Kind | Preinstalled | `runs-on` labels |
|------|--------------|------------------|
| **Rust** | rustup, cargo, clippy, rustfmt + native build deps | `[self-hosted, rust]` |
| **Node** | Node.js LTS + npm, pnpm, yarn | `[self-hosted, node]` |
| **Python** | Python 3 + pip/venv + uv | `[self-hosted, python]` |
| **Go** | official Go toolchain | `[self-hosted, go]` |
| **Base** | `gh`, Docker CLI/Compose/Buildx, Node.js 24/npm, portable shell tools | `[self-hosted]` |

The images live in `images/<kind>.Dockerfile` (all build `FROM gha-runner:base`) — add your
own kind by dropping in a new Dockerfile and a matching entry in `app/internal/kinds/kinds.go`.

> **Auth note:** `gha` passes your `gh` OAuth token into each container as `GITHUB_PAT`, so
> registration tokens **auto-refresh on restart** (a one-shot token would expire after ~1h).
> Treat it like any credential; only attach runners to repos/orgs you trust.

### Networking — no static IP, no open ports

A self-hosted runner makes an **outbound** long-poll to GitHub and receives jobs over it —
GitHub never connects *in*. So:

- **No static IP** — a dynamic/home IP is fine; it just reconnects if it changes.
- **No port forwarding / inbound ports** — works behind NAT, CGNAT, and typical firewalls.
- The **only** requirement is **outbound HTTPS (443)** to GitHub. Verify it any time with
  `gha netcheck` (or `gha up` runs it automatically).

**Behind a proxy / locked-down egress?** The wizard has optional **HTTPS proxy** and
**no-proxy** fields (prefilled from `HTTPS_PROXY` / `NO_PROXY` if set). Whatever you enter is
passed into every runner container, and `entrypoint.sh` + the runner honor it. If egress is
filtered, allowlist: `github.com`, `api.github.com`, `*.actions.githubusercontent.com`,
`codeload.github.com`, `objects.githubusercontent.com`, and `*.blob.core.windows.net`.

---

## Quick start — shell scripts (alternative, no Go/gh needed)

Run the setup script for your OS; it prompts for the URL, PAT, and runner name(s),
then builds the image and launches each runner as an auto-restarting service. You
can create several at once with comma-separated names:

```bash
./setup.sh          # Linux / macOS   (Windows: ./setup.ps1)
# GitHub URL:        https://github.com/Verjson
# GitHub PAT:        ********
# Runner name(s):    ci-runner-01, ci-runner-02
# Labels:            self-hosted,linux,x64,docker
# Runner group:      Default          <- press Enter unless you created a group (see below)
# Work folder:       _work
```

All of these are collected from you at the prompts, so nothing is hardcoded. The
**runner group** defaults to `Default` (works out of the box); only change it if
you've created a custom group in the org first — see [Runner groups](#runner-groups-org-runners-only).

Each name becomes its own container `gha-<name>` with `--restart unless-stopped`
(so it also survives reboots while the Docker daemon is enabled).

```bash
docker ps --filter name=gha-           # see them
docker logs -f gha-ci-runner-01        # wait for "Listening for Jobs"
docker rm -f gha-ci-runner-01          # stop one
```

Target them in a workflow:
```yaml
jobs:
  build:
    runs-on: [self-hosted, docker]
    steps:
      - uses: actions/checkout@v4
      - run: echo "running on my self-hosted runner"
```

## Alternative — single runner via compose

1. Edit `.env` (`GITHUB_URL`, `GITHUB_PAT`, `RUNNER_NAME`, `RUNNER_LABELS`).
   - Org runner → classic PAT with `admin:org`.
   - Repo runner → classic PAT with `repo`.
2. `docker compose up -d --build` then `docker compose logs -f`.
3. `docker compose down` stops and cleanly de-registers it.

## Runner groups (org runners only)

A **runner group** lets an org organize runners and control **which repositories**
may use them. It only applies to **organization** (and enterprise) runners — repo-level
runners have no groups. The default group is `Default`, and the setup prompt defaults
to it, so you can ignore groups entirely unless you want the access control.

> ⚠️ `config.sh` can only **assign** a runner to a group that **already exists** — it
> cannot create one. If you enter a group name that doesn't exist, registration fails.

**To create a new group and use it:**

1. On GitHub: **Org → Settings → Actions → Runner groups → New runner group**.
2. Give it a **name** (e.g. `manish`), set **Repository access** (all repos, or select
   specific ones), optionally restrict to selected workflows, then **Create**.
3. Run the setup and enter that exact name at the **Runner group** prompt:
   ```bash
   ./setup.sh
   # ...
   # Runner group (org runners only; Default for repo): manish
   ```
   (Or set `RUNNER_GROUP=manish` in `.env` for the compose path.)
4. Verify: the runner appears under that group in **Settings → Actions → Runners**.

## Files
| File | Purpose |
|------|---------|
| `setup.sh` | Interactive CLI for **Linux / macOS** — prompts, builds, launches N runners as services. |
| `setup.ps1` | Interactive CLI for **Windows** (PowerShell) — same flow. |
| `images/base.Dockerfile` | Base runner image (Ubuntu 24.04, non-root `runner`, shared `ci` tools). Every kind builds `FROM` it. |
| `images/<kind>.Dockerfile` | Language kinds (rust/node/python/go) layered on the base. |
| `.github/workflows/publish-images.yml` | CI: build + push attested multi-arch images and retain immutable digest receipts. |
| `entrypoint.sh` | Admits the exact `ci` contract before credentials, mints/uses a registration token, runs, and de-registers on stop. |
| `docker-compose.yml` | Single-runner alternative (`restart: unless-stopped`). |
| `.env` | Config + secrets for the compose path (git-ignored). |

> The root `Dockerfile` is a pre-`images/` leftover kept only for backward compat — the
> live image is `images/base.Dockerfile`.

## Notes
- **Token options** (`entrypoint.sh`, in order of preference):
  - `GITHUB_PAT` — recommended for a host you control; self-refreshes each start/stop.
  - `RUNNER_TOKEN_CMD` — a command that prints a fresh registration token each start,
    so a host injects its own minting (GCP passes the VM's App-key mint script — no
    PAT/private key on the box) and still gets PAT-style refresh.
  - `RUNNER_REMOVE_TOKEN_CMD` — optional command that prints a fresh removal token
    on container cleanup/stop.
  - `RUNNER_TOKEN` — a one-shot token (expires ~1h; stop leaves an offline "ghost").
- **Environment overrides** (`entrypoint.sh`):
  - `RUNNER_DIR` — optional working directory override containing `actions-runner` binaries (defaults to `/home/runner/actions-runner`).
  - `RUNNER_EPHEMERAL` — if set to `1` or `true`, passes `--ephemeral` to `./config.sh` so the runner tears down after completing a single job.
  - `RUNNER_LABELS` — comma-separated labels. Advertising the exact `ci` label cannot
    bypass startup admission.
- **Docker-in-CI:** the base image already includes the Docker CLI + buildx + compose
  plugins. To let workflows use them, mount the host socket at run time
  (`-v /var/run/docker.sock:/var/run/docker.sock`, or uncomment it in
  `docker-compose.yml`). This grants host root-equivalent access — trusted private
  repos only.
- **Security & Hardening:** See [SECURITY.md](file:///d:/Development/verjson/verjson-github-runner/SECURITY.md) for full threat model details, ephemeral runner enforcement (`RUNNER_EPHEMERAL=1`), least-privilege token permissions, IMDS isolation, and incident response procedures.
- **Availability:** keep the host awake (disable sleep) or jobs queue while it's off.
- **Update the runner:** bump `RUNNER_VERSION` in the `Dockerfile`, then
  `docker compose up -d --build`.
