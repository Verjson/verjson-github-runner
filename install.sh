#!/usr/bin/env bash
#
# Curl-pipe installer. Clones the repo, then runs bootstrap.sh (which installs Docker + gh,
# builds the `gha` manager, and launches it). Intended for:
#
#     curl -fsSL https://raw.githubusercontent.com/Verjson/github-runner-docker-compose/main/install.sh | bash
#
# Overrides (env vars):
#     GHA_DIR=/opt/github-runner   # where to clone   (default: ~/github-runner)
#     GHA_REF=some-branch          # branch/tag/sha   (default: main)
# Pass-through flags go to bootstrap.sh, e.g.  ... | bash -s -- --no-run
set -euo pipefail

REPO="https://github.com/Verjson/github-runner-docker-compose.git"
DIR="${GHA_DIR:-$HOME/github-runner}"
REF="${GHA_REF:-main}"

log()  { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# Reconnect stdin to the terminal so interactive prompts (gh login, the wizard) work even
# though this script itself arrived over a pipe. If there's no TTY, we set up but don't launch.
NO_TTY=0
if [ ! -t 0 ]; then
  if [ -r /dev/tty ]; then exec </dev/tty; else NO_TTY=1; fi
fi

# git is required to clone.
if ! command -v git >/dev/null 2>&1; then
  log "Installing git…"
  if   command -v brew    >/dev/null 2>&1; then brew install git
  elif command -v apt-get >/dev/null 2>&1; then $SUDO apt-get update && $SUDO apt-get install -y git
  elif command -v dnf     >/dev/null 2>&1; then $SUDO dnf install -y git
  elif command -v yum     >/dev/null 2>&1; then $SUDO yum install -y git
  elif command -v pacman  >/dev/null 2>&1; then $SUDO pacman -Sy --noconfirm git
  elif command -v apk     >/dev/null 2>&1; then $SUDO apk add git
  else die "git is required but not installed, and no known package manager was found"
  fi
fi

# Clone fresh, or update an existing checkout.
if [ -d "$DIR/.git" ]; then
  log "Updating existing checkout in $DIR"
  git -C "$DIR" fetch --depth 1 origin "$REF"
  git -C "$DIR" checkout -q "$REF"
  git -C "$DIR" reset -q --hard "origin/$REF" 2>/dev/null || git -C "$DIR" reset -q --hard FETCH_HEAD
else
  log "Cloning $REPO → $DIR"
  git clone --depth 1 --branch "$REF" "$REPO" "$DIR" 2>/dev/null \
    || git clone "$REPO" "$DIR"   # fallback if REF is a full sha
fi

cd "$DIR"
chmod +x bootstrap.sh 2>/dev/null || true

if [ "$NO_TTY" = 1 ]; then
  log "No terminal detected — setting up without launching."
  ./bootstrap.sh --no-run "$@"
  echo
  log "Done. To launch:  cd \"$DIR\" && ./gha up"
else
  exec ./bootstrap.sh "$@"
fi
