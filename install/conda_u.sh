#!/usr/bin/env bash
set -euo pipefail

# Ubuntu-only Miniconda3 installer
# - No Python dependency
# - Supports x86_64 and aarch64
# - Optional SHA-256 verification
# - Installs to $HOME/miniconda3 by default
#
# Usage:
#   chmod +x install_miniconda3_ubuntu.sh
#   ./install_miniconda3_ubuntu.sh
#
# Optional env vars:
#   INSTALL_DIR="$HOME/miniconda3"
#   INIT_SHELL="bash"          # bash | zsh | fish
#   AUTO_ACTIVATE_BASE="false" # true | false
#   VERIFY_SHA256="false"      # true | false

INSTALL_DIR="${INSTALL_DIR:-$HOME/miniconda3}"
INIT_SHELL="${INIT_SHELL:-bash}"
AUTO_ACTIVATE_BASE="${AUTO_ACTIVATE_BASE:-false}"
VERIFY_SHA256="${VERIFY_SHA256:-false}"

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)
      echo "x86_64"
      ;;
    aarch64)
      echo "aarch64"
      ;;
    *)
      die "Unsupported architecture: $arch (supported: x86_64, aarch64)"
      ;;
  esac
}

check_ubuntu_or_debian() {
  if ! command -v dpkg >/dev/null 2>&1; then
    die "dpkg not found. This script is intended for Ubuntu/Debian-like systems."
  fi
}

check_glibc() {
  local glibc_version
  glibc_version="$(ldd --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"

  if [[ -z "$glibc_version" ]]; then
    warn "Unable to detect glibc version automatically. Continuing."
    return 0
  fi

  log "Detected glibc: $glibc_version"
  if ! dpkg --compare-versions "$glibc_version" ge 2.28; then
    die "glibc $glibc_version is too old. Latest Miniconda installers require glibc >= 2.28."
  fi
}

download_file() {
  local url="$1"
  local out="$2"

  if command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -L "$url" -o "$out"
  else
    die "Neither wget nor curl is installed."
  fi
}

fetch_official_sha256() {
  local installer_name="$1"
  local page
  page="$(curl -fsSL https://repo.anaconda.com/miniconda/ || true)"
  [[ -n "$page" ]] || return 1

  # Parse the SHA256 that appears on the same line as the installer filename.
  # Works with the current simple index listing format.
  echo "$page" | awk -v name="$installer_name" '
    $0 ~ name {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[a-f0-9]{64}$/) {
          print $i
          exit
        }
      }
    }
  '
}

verify_sha256() {
  local file="$1"
  local installer_name="$2"

  require_cmd sha256sum
  require_cmd curl

  log "Fetching official SHA-256 for $installer_name ..."
  local official actual
  official="$(fetch_official_sha256 "$installer_name" || true)"
  [[ -n "$official" ]] || die "Unable to fetch official SHA-256 from repo.anaconda.com."

  actual="$(sha256sum "$file" | awk '{print $1}')"

  log "Official SHA-256: $official"
  log "Actual   SHA-256: $actual"

  [[ "$official" == "$actual" ]] || die "SHA-256 mismatch. Aborting."
}

init_conda() {
  local conda_bin="$INSTALL_DIR/bin/conda"
  [[ -x "$conda_bin" ]] || die "conda binary not found at $conda_bin"

  "$conda_bin" init "$INIT_SHELL"

  if [[ "$AUTO_ACTIVATE_BASE" == "false" ]]; then
    "$conda_bin" config --set auto_activate_base false
  fi
}

main() {
  check_ubuntu_or_debian
  check_glibc

  local arch installer installer_url installer_path
  arch="$(detect_arch)"
  installer="Miniconda3-latest-Linux-${arch}.sh"
  installer_url="https://repo.anaconda.com/miniconda/${installer}"
  installer_path="/tmp/${installer}"

  log "Architecture: $arch"
  log "Installer URL: $installer_url"
  log "Install dir: $INSTALL_DIR"

  if [[ -e "$INSTALL_DIR" ]]; then
    die "Install directory already exists: $INSTALL_DIR"
  fi

  log "Downloading installer ..."
  download_file "$installer_url" "$installer_path"

  if [[ "$VERIFY_SHA256" == "true" ]]; then
    verify_sha256 "$installer_path" "$installer"
  else
    log "Skipping SHA-256 verification (VERIFY_SHA256=false)"
  fi

  log "Running silent install ..."
  bash "$installer_path" -b -p "$INSTALL_DIR"

  log "Initializing conda for shell: $INIT_SHELL"
  init_conda

  log "Verifying installation ..."
  "$INSTALL_DIR/bin/conda" --version
  "$INSTALL_DIR/bin/conda" info --base

  echo
  echo "Done."
  echo "Next step:"
  case "$INIT_SHELL" in
    bash) echo "  source ~/.bashrc" ;;
    zsh)  echo "  source ~/.zshrc" ;;
    fish) echo "  source ~/.config/fish/config.fish" ;;
    *)    echo "  reopen your shell" ;;
  esac
}

main "$@"
