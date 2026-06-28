#!/usr/bin/env bash
# Verify GPU is present and accessible to both inference backends before any upscale job.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL  %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# 1. NVIDIA driver accessible
if nvidia-smi >/dev/null 2>&1; then
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  ok "nvidia-smi: $GPU_NAME"
else
  fail "nvidia-smi not found or GPU inaccessible"
fi

# 2. CUDA version legible
CUDA_VER=$(nvidia-smi 2>/dev/null | grep -oP 'CUDA Version: \K[0-9.]+' || true)
if [ -n "$CUDA_VER" ]; then
  ok "CUDA version: $CUDA_VER"
else
  fail "Could not determine CUDA version from nvidia-smi"
fi

# 3. Real-ESRGAN: venv python imports torch and reports CUDA device
VENV_PYTHON="$PROJECT_ROOT/tools/realesrgan/venv/bin/python"
if [ -f "$VENV_PYTHON" ]; then
  # Capture exit code explicitly — set -e would abort the script if we
  # let the command substitution fail without || handling.
  _torch_ec=0
  TORCH_GPU=$("$VENV_PYTHON" - 2>/dev/null <<'EOF'
import torch, sys
if torch.cuda.is_available():
    print(torch.cuda.get_device_name(0))
else:
    sys.exit(1)
EOF
) || _torch_ec=$?
  if [ "$_torch_ec" -eq 0 ] && [ -n "$TORCH_GPU" ]; then
    ok "torch CUDA device: $TORCH_GPU"
  else
    fail "torch.cuda.is_available() returned False — Real-ESRGAN will run on CPU"
  fi
else
  fail "Real-ESRGAN venv not found at $VENV_PYTHON — run scripts/setup.sh"
fi

# 4. Video2X: Vulkan device visible (RTX or discrete GPU, not llvmpipe only)
VIDEO2X="${VIDEO2X:-}"
if [ -z "$VIDEO2X" ]; then
  if [ -f "$PROJECT_ROOT/tools/video2x/video2x" ]; then
    VIDEO2X="$PROJECT_ROOT/tools/video2x/video2x"
  elif command -v video2x >/dev/null 2>&1; then
    VIDEO2X=video2x
  fi
fi

if [ -n "$VIDEO2X" ] && [ -x "$VIDEO2X" ]; then
  V2X_DEVICES=$("$VIDEO2X" --help 2>&1 | grep -i vulkan || true)
  # Check a Vulkan ICD is present for NVIDIA. Scan only dirs that exist: `find` on a missing
  # operand exits non-zero, which under `set -o pipefail` masks a successful grep match (the
  # ICD dir layout varies by distro — /etc/vulkan/icd.d is absent on Omarchy/Arch).
  _icd_found=0
  for _d in /usr/share/vulkan/icd.d /etc/vulkan/icd.d /usr/local/share/vulkan/icd.d; do
    [ -d "$_d" ] || continue
    if find "$_d" -iname '*nvidia*' 2>/dev/null | grep -qi nvidia; then _icd_found=1; break; fi
  done
  if [ "$_icd_found" -eq 0 ] && ldconfig -p 2>/dev/null | grep -q 'libGLX_nvidia'; then
    _icd_found=1
  fi
  if [ "$_icd_found" -eq 1 ]; then
    ok "Vulkan NVIDIA ICD present (video2x GPU acceleration available)"
  else
    fail "No NVIDIA Vulkan ICD found — video2x will fall back to CPU"
  fi
else
  fail "video2x binary not found — run scripts/setup.sh"
fi

# Summary
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
