#!/usr/bin/env bash
set -euo pipefail

# Auto-route PyTorch installer for your three-machine setup:
# - Tesla P40 / Pascal      -> cu118
# - RTX 2060 / Turing       -> cu130 > cu129 > cu118
# - RTX 5060 Ti / Blackwell -> cu130 > cu129
#
# Optional env vars:
#   ENV_NAME=vit-auto
#   PY_VER=3.11
#   ROUTE_OVERRIDE=cu118|cu129|cu130|cpu
#
# Usage:
#   chmod +x install_pytorch_autoroute.sh
#   ./install_pytorch_autoroute.sh

ENV_NAME="${ENV_NAME:-vit-auto}"
PY_VER="${PY_VER:-3.11}"
ROUTE_OVERRIDE="${ROUTE_OVERRIDE:-}"

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

version_ge() {
  # usage: version_ge "580.65.06" "575.51.03"
  dpkg --compare-versions "$1" ge "$2"
}

detect_gpu_names() {
  nvidia-smi --query-gpu=name --format=csv,noheader
}

detect_driver_version() {
  nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d ' '
}

classify_machine() {
  local names="$1"

  # Blackwell / RTX 50 series first
  if echo "$names" | grep -Eqi 'RTX 50|RTX 5060|RTX 5070|RTX 5080|RTX 5090'; then
    echo "blackwell"
    return
  fi

  # Pascal
  if echo "$names" | grep -Eqi 'Tesla P40|Tesla P4|Tesla P100|GTX 10|Pascal'; then
    echo "pascal"
    return
  fi

  # Turing / RTX 20
  if echo "$names" | grep -Eqi 'RTX 2060|RTX 2070|RTX 2080|Turing|Tesla T4'; then
    echo "turing"
    return
  fi

  # Ampere / Ada fallback buckets if you later reuse script elsewhere
  if echo "$names" | grep -Eqi 'RTX 30|A30|A40|A100|Ampere'; then
    echo "ampere"
    return
  fi
  if echo "$names" | grep -Eqi 'RTX 40|Ada|L4|L40'; then
    echo "ada"
    return
  fi

  echo "unknown"
}

choose_route() {
  local family="$1"
  local driver="$2"

  if [[ -n "$ROUTE_OVERRIDE" ]]; then
    echo "$ROUTE_OVERRIDE"
    return
  fi

  case "$family" in
    pascal)
      # Conservative choice for Pascal
      if version_ge "$driver" "450.80.02"; then
        echo "cu118"
      else
        die "Driver $driver is too old even for cu118/Pascal. Need >= 450.80.02."
      fi
      ;;
    turing|ampere|ada)
      if version_ge "$driver" "580.65.06"; then
        echo "cu130"
      elif version_ge "$driver" "575.51.03"; then
        echo "cu129"
      elif version_ge "$driver" "450.80.02"; then
        echo "cu118"
      else
        die "Driver $driver is too old. Need >= 450.80.02 at minimum."
      fi
      ;;
    blackwell)
      if version_ge "$driver" "580.65.06"; then
        echo "cu130"
      elif version_ge "$driver" "575.51.03"; then
        echo "cu129"
      else
        die "Blackwell detected, but driver $driver is too old for cu129/cu130. Please update driver."
      fi
      ;;
    unknown)
      warn "Unknown GPU family. Falling back by driver only."
      if version_ge "$driver" "580.65.06"; then
        echo "cu130"
      elif version_ge "$driver" "575.51.03"; then
        echo "cu129"
      elif version_ge "$driver" "450.80.02"; then
        echo "cu118"
      else
        echo "cpu"
      fi
      ;;
    *)
      die "Unhandled GPU family: $family"
      ;;
  esac
}

install_torch() {
  local route="$1"

  python -m pip install --upgrade pip

  case "$route" in
    cu118)
      pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu118
      ;;
    cu129)
      pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu129
      ;;
    cu130)
      pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu130
      ;;
    cpu)
      pip install torch torchvision torchaudio
      ;;
    *)
      die "Unknown install route: $route"
      ;;
  esac
}

verify_install() {
  python - <<'PY'
import torch, sys
print("torch:", torch.__version__)
print("torch.version.cuda:", torch.version.cuda)
print("cuda.is_available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("device_count:", torch.cuda.device_count())
    for i in range(torch.cuda.device_count()):
        print(f"gpu[{i}]:", torch.cuda.get_device_name(i))
PY
}

main() {
  require_cmd conda
  require_cmd dpkg

  source "$(conda info --base)/etc/profile.d/conda.sh"

  if [[ -z "${ROUTE_OVERRIDE}" ]]; then
    require_cmd nvidia-smi
    GPU_NAMES="$(detect_gpu_names)"
    DRIVER_VER="$(detect_driver_version)"
    FAMILY="$(classify_machine "$GPU_NAMES")"

    log "Detected GPUs:"
    echo "$GPU_NAMES" | sed 's/^/  - /'
    log "Detected driver: $DRIVER_VER"
    log "Classified family: $FAMILY"

    ROUTE="$(choose_route "$FAMILY" "$DRIVER_VER")"
  else
    ROUTE="$ROUTE_OVERRIDE"
    log "Using manual override route: $ROUTE"
  fi

  log "Selected route: $ROUTE"
  conda create -y -n "$ENV_NAME" python="$PY_VER"
  conda activate "$ENV_NAME"

  install_torch "$ROUTE"
  verify_install

  log "Done."
  log "Activate later with: conda activate $ENV_NAME"
}

main "$@"
