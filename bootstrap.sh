#!/usr/bin/env bash
#
# One script for Linux, macOS, and Windows (via WSL2).
#
# It installs whatever is missing (Docker, GitHub CLI), builds the `gha` manager, then
# launches it. Run it once on a freshly-cloned repo:
#
#     ./bootstrap.sh            # install what's missing, build, then run `gha up`
#     ./bootstrap.sh --no-run   # install + build only (don't launch)
#     ./bootstrap.sh --help
#
# Platforms:
#   • Linux   — apt / dnf / yum / pacman / apk (Docker via get.docker.com)
#   • macOS   — Homebrew (Docker Desktop + gh)
#   • Windows — run this inside WSL2 (Ubuntu); it's just the Linux path. Docker Desktop
#               with the WSL2 backend runs the Linux runner containers.
#
# Go is NOT required on the host: if a suitable Go isn't present, the binary is built
# inside a golang container.
set -euo pipefail
cd "$(dirname "$0")"

# ---------- pretty output ----------
log()  { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m ✓ \033[0m%s\n' "$*"; }
warn() { printf '\033[0;33m ! \033[0m%s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

RUN_AFTER=1
for arg in "$@"; do
  case "$arg" in
    --no-run) RUN_AFTER=0 ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
    *) die "unknown flag: $arg (try --help)" ;;
  esac
done

# ---------- environment detection ----------
OS="$(uname -s)"                       # Linux | Darwin
IS_WSL=0; grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && IS_WSL=1
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
if [ -n "$SUDO" ] && ! command -v sudo >/dev/null 2>&1; then
  die "not root and 'sudo' is missing; re-run as root"
fi

PM=""
for c in brew apt-get dnf yum pacman apk; do
  if command -v "$c" >/dev/null 2>&1; then PM="$c"; break; fi
done

# ---------- Docker ----------
install_docker() {
  if command -v docker >/dev/null 2>&1; then ok "Docker already installed"; return; fi
  log "Installing Docker…"
  if [ "$OS" = "Darwin" ]; then
    command -v brew >/dev/null 2>&1 || die "Install Homebrew (https://brew.sh) or Docker Desktop, then re-run"
    brew install --cask docker || die "Docker Desktop install failed"
    open -a Docker 2>/dev/null || true
    warn "Docker Desktop installed. Start it (whale icon), wait until it's running, then re-run ./bootstrap.sh"
    exit 0
  fi
  # Linux (incl. WSL2). On WSL, Docker Desktop's WSL integration is the usual route.
  if [ "$IS_WSL" = 1 ] && ! command -v docker >/dev/null 2>&1; then
    warn "On Windows, install Docker Desktop and enable WSL integration for this distro:"
    warn "  https://docs.docker.com/desktop/wsl/  — then re-run ./bootstrap.sh"
  fi
  curl -fsSL https://get.docker.com | $SUDO sh || die "Docker install failed"
  $SUDO systemctl enable --now docker 2>/dev/null || true
  if [ -n "$SUDO" ]; then $SUDO usermod -aG docker "$USER" && ADDED_DOCKER_GROUP=1 || true; fi
  ok "Docker installed"
}

# ---------- GitHub CLI ----------
install_gh() {
  if command -v gh >/dev/null 2>&1; then ok "GitHub CLI already installed"; return; fi
  log "Installing GitHub CLI (gh)…"
  case "$PM" in
    brew) brew install gh ;;
    apt-get)
      command -v wget >/dev/null 2>&1 || $SUDO apt-get install -y wget
      $SUDO mkdir -p -m 755 /etc/apt/keyrings
      wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
      $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      $SUDO apt-get update && $SUDO apt-get install -y gh ;;
    dnf) $SUDO dnf install -y 'dnf-command(config-manager)' && $SUDO dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && $SUDO dnf install -y gh ;;
    yum) $SUDO yum install -y gh || die "install gh manually: https://cli.github.com" ;;
    pacman) $SUDO pacman -Sy --noconfirm github-cli ;;
    apk) $SUDO apk add github-cli ;;
    *) die "could not install gh automatically — see https://cli.github.com" ;;
  esac
  ok "GitHub CLI installed"
}

# ---------- helpers ----------
docker_cli() {
  if docker info >/dev/null 2>&1; then echo "docker"; return; fi
  if $SUDO docker info >/dev/null 2>&1; then echo "$SUDO docker"; return; fi
  echo "docker"
}

# host Go present and >= 1.22 ?
go_ok() {
  command -v go >/dev/null 2>&1 || return 1
  local v; v="$(go env GOVERSION 2>/dev/null | sed 's/^go//')"
  awk -v v="$v" 'BEGIN{n=split(v,a,"."); if (a[1]>1 || (a[1]==1 && a[2]>=22)) exit 0; exit 1}'
}

# ---------- build ----------
build_gha() {
  if go_ok; then
    log "Building gha with host Go ($(go env GOVERSION))…"
    ( cd app && go build -o ../gha . )
  else
    warn "No suitable host Go — building inside a golang:1.22 container (no Go install needed)…"
    local D; D="$(docker_cli)"
    $D info >/dev/null 2>&1 || die "Docker daemon isn't running yet; start it and re-run ./bootstrap.sh"
    # -buildvcs=false: inside the container the repo's .git is owned by a different UID,
    # which otherwise trips Go's VCS-stamping ownership check.
    $D run --rm -v "$PWD":/src -w /src/app golang:1.22 \
      go build -buildvcs=false -o ../gha . || die "container build failed"
  fi
  [ -x ./gha ] || die "build did not produce ./gha"
  ok "Built ./gha"
}

# ---------- launch ----------
run_gha() {
  [ "$RUN_AFTER" = 1 ] || { log "Done. Launch it with:  ./gha up"; return; }
  if docker info >/dev/null 2>&1; then
    log "Launching gha up …"; echo; exec ./gha up
  fi
  if [ "$OS" = "Darwin" ]; then
    warn "Docker daemon isn't running. Start Docker Desktop, then run:  ./gha up"; exit 0
  fi
  if [ "${ADDED_DOCKER_GROUP:-0}" = 1 ] && command -v sg >/dev/null 2>&1; then
    warn "Activating the 'docker' group for this session (avoids a re-login)…"; echo
    exec sg docker -c "$PWD/gha up"
  fi
  if $SUDO docker info >/dev/null 2>&1; then
    warn "Log out/in to pick up the 'docker' group, then run  ./gha up  (or now: sudo ./gha up)"; exit 0
  fi
  warn "Docker daemon not reachable. Start it (sudo systemctl start docker), then run  ./gha up"; exit 0
}

log "Bootstrapping GitHub runner manager  (OS: $OS${IS_WSL:+, WSL})"
install_docker
install_gh
build_gha
echo
run_gha
