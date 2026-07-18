# Session notes

Working state and caveats for the `gha` runner-manager work. Living doc — update as things land.

## What was built

- **`gha` manager (Go, `app/`)** — one binary that manages many Dockerized GitHub Actions
  self-hosted runners:
  - **Wizard** (`gha add`): pick an org/repo (listed via `gh`, or typed), multi-select which
    language **kinds**, and set **how many of each** on one screen; labels/group/ephemeral;
    optional **HTTPS proxy**.
  - **Live dashboard** (`gha dashboard`, aliases `dash`/`top`): btop-style table with state,
    CPU/mem, current job; keys `l` logs · `r` restart · `s` stop · `q` quit.
  - **Auth via GitHub CLI** — no PAT paste. `gh auth token` is passed into containers as
    `GITHUB_PAT` so registration tokens **auto-refresh on restart**. Missing scope →
    offers `gh auth refresh`.
  - **`gha up`** — one command: docker check → `gh auth login` if needed → network preflight
    → wizard.
  - **`gha netcheck`** — verifies outbound **443** to GitHub (TLS handshake probe; honors
    `HTTPS_PROXY`). States clearly that inbound/static-IP are **not** required.
- **Runner "kinds"** (`images/*.Dockerfile`) — `base` + `rust`/`node`/`python`/`go`, each a
  thin layer over `gha-runner:base` that preinstalls the toolchain and sets `runs-on` labels.
- **One-command setup**:
  - `install.sh` (curl-pipe) — clones the repo, reconnects the TTY for interactive prompts,
    hands off to `bootstrap.sh`.
  - `bootstrap.sh` — installs Docker + `gh` if missing, builds `gha` (host Go ≥1.22, else a
    `golang:1.22` container so **no host Go needed**), then launches. Linux / macOS /
    Windows-via-WSL2.

## Networking (the recurring question)

- **No static IP, no inbound/forwarded ports.** Runner makes an outbound long-poll to GitHub.
- Only requirement is **outbound 443**. `gha netcheck` / `gha up` check it.
- Locked-down egress → wizard's HTTPS-proxy fields flow into every container; allowlist:
  `github.com, api.github.com, *.actions.githubusercontent.com, codeload.github.com,
  objects.githubusercontent.com, *.blob.core.windows.net`.

## Verified

- Builds (host **and** `golang:1.22` container), `go vet`, `gofmt`, unit tests
  (target/job parsing, dashboard render, netcheck) all pass.
- All shell scripts pass `bash -n`.
- **Real** `gha netcheck` against GitHub — all endpoints reachable.
- Fixed along the way: HTTP-HEAD probe gave a false negative on the blob store → switched to
  TLS-handshake probe; container build tripped Go VCS stamping → added `-buildvcs=false`.

## NOT yet verified (needs a real box)

- Actual `apt`/`brew` installs in `bootstrap.sh`/`install.sh`.
- Live `gha up` end-to-end: `gh auth login` → token → image build → container launch against
  a real repo/org. (`gh` isn't installed on the dev machine used this session.)

## curl one-liner caveat

README shows:
```
curl -fsSL https://raw.githubusercontent.com/Verjson/github-runner-docker-compose/main/install.sh | bash
```
This reads `install.sh` from **`main`**, which does **not** have these files yet (work is on
`manish_dev`). Until merged to `main`, test with the installer + clone both from the branch:
```
curl -fsSL https://raw.githubusercontent.com/Verjson/github-runner-docker-compose/manish_dev/install.sh | GHA_REF=manish_dev bash
```

## Remaining steps

1. Merge `manish_dev` → `main` so the clean curl one-liner works.
2. Run `./bootstrap.sh` (or the branch curl command) on a real server to validate installs +
   a live `gha up`.
3. Optional follow-ups discussed: a `Makefile`, a "remove all runners" command, deeper
   docker-socket-mount toggle.
