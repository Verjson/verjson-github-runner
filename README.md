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

## Quick start — interactive CLI (recommended)

Run the setup script for your OS; it prompts for the URL, PAT, and runner name(s),
then builds the image and launches each runner as an auto-restarting service. You
can create several at once with comma-separated names:

```bash
./setup.sh          # Linux / macOS   (Windows: ./setup.ps1)
# GitHub URL: https://github.com/Verjson
# GitHub PAT: ********
# Runner name(s): ci-runner-01, ci-runner-02
# Labels: self-hosted,linux,x64,docker
```

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

## Files
| File | Purpose |
|------|---------|
| `setup.sh` | Interactive CLI for **Linux / macOS** — prompts, builds, launches N runners as services. |
| `setup.ps1` | Interactive CLI for **Windows** (PowerShell) — same flow. |
| `Dockerfile` | Builds the multi-arch runner image (Ubuntu 24.04, non-root `runner`, runner v2.335.1). |
| `entrypoint.sh` | Registers on start, runs, and de-registers on stop. |
| `docker-compose.yml` | Single-runner alternative (`restart: unless-stopped`). |
| `.env` | Config + secrets for the compose path (git-ignored). |

## Notes
- **Token options:** `GITHUB_PAT` (recommended, self-refreshing) or a one-shot
  `RUNNER_TOKEN` (expires ~1h; stop leaves an offline "ghost" entry).
- **Docker-in-CI:** to let workflows run `docker build`/`docker run`, uncomment the
  `docker.sock` mount in `docker-compose.yml` and add the Docker CLI to the image.
  This grants host root-equivalent access — trusted private repos only.
- **Security:** a self-hosted runner executes whatever workflow code is submitted.
  Never attach it to a public repo where outside PRs could run code on your machine.
- **Availability:** keep the host awake (disable sleep) or jobs queue while it's off.
- **Update the runner:** bump `RUNNER_VERSION` in the `Dockerfile`, then
  `docker compose up -d --build`.
