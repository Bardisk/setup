#!/usr/bin/env bash
set -euo pipefail

# =========================
# Ubuntu Miniconda3 installer
# =========================

INSTALL_DIR="${HOME}/miniconda3"
# Disable auto activate by default
AUTO_ACTIVATE_BASE="false"
INIT_SHELL="bash"
VERIFY_GLIBC="true"

echo "[1/7] Detecting architecture..."
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)
    INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
    ;;
  aarch64)
    INSTALLER="Miniconda3-latest-Linux-aarch64.sh"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}"
    echo "Supported: x86_64, aarch64"
    exit 1
    ;;
esac

INSTALLER_URL="https://repo.anaconda.com/miniconda/${INSTALLER}"
INSTALLER_PATH="/tmp/${INSTALLER}"

if [[ "${VERIFY_GLIBC}" == "true" ]]; then
  echo "[2/7] Checking glibc version..."
  GLIBC_VERSION="$(ldd --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
  if [[ -z "${GLIBC_VERSION}" ]]; then
    echo "Warning: unable to detect glibc version automatically."
  else
    echo "Detected glibc: ${GLIBC_VERSION}"
    python3 - <<PY
import sys
from packaging.version import Version
v = Version("${GLIBC_VERSION}")
if v < Version("2.28"):
    print("glibc < 2.28, latest Miniconda installer may not work.")
    sys.exit(1)
PY
  fi
fi

if [[ -d "${INSTALL_DIR}" ]]; then
  echo "[3/7] ${INSTALL_DIR} already exists."
  echo "Remove it first if you want a clean reinstall."
  exit 1
fi

echo "[4/7] Downloading installer..."
wget -O "${INSTALLER_PATH}" "${INSTALLER_URL}"

echo "[5/7] Running silent install..."
bash "${INSTALLER_PATH}" -b -p "${INSTALL_DIR}"

echo "[6/7] Initializing conda for ${INIT_SHELL}..."
source "${INSTALL_DIR}/bin/activate"
conda init "${INIT_SHELL}"

if [[ "${AUTO_ACTIVATE_BASE}" == "false" ]]; then
  conda config --set auto_activate_base false
fi

echo "[7/7] Verifying install..."
"${INSTALL_DIR}/bin/conda" --version
"${INSTALL_DIR}/bin/conda" info --base

echo
echo "Done."
echo "Now run:"
echo "  source ~/.bashrc"
echo "or reopen your terminal."
