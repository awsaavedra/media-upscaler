#!/usr/bin/env bash
# Installs video2x and Real-ESRGAN into tools/ within this repository.
#
# Usage:  ./scripts/setup.sh        (no sudo, no system packages)
#
# Self-contained / in-directory: torch + Real-ESRGAN live in an isolated venv under tools/,
# built on a project-local Python 3.12 (provisioned via mise/uv) so the proven cu118 wheels
# install cleanly. We deliberately avoid the system Python — modern distros ship 3.13/3.14,
# where (a) cu118 wheels don't publish and (b) basicsr's setup.py breaks on the PEP 667
# locals() change. Same path works identically on Mac/Ubuntu/WSL2/Omarchy. See docs/roadmap.md §v3.0 (open image-stack decision).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$PROJECT_ROOT/tools"
VIDEO2X_DIR="$TOOLS_DIR/video2x"
REALESRGAN_DIR="$TOOLS_DIR/realesrgan"

VIDEO2X_VERSION="6.4.0"
VIDEO2X_APPIMAGE="Video2X-x86_64.AppImage"
VIDEO2X_URL="https://github.com/k4yt3x/video2x/releases/download/${VIDEO2X_VERSION}/${VIDEO2X_APPIMAGE}"

log() { printf '[setup] %s\n' "$*"; }
die() { printf '[setup] ERROR: %s\n' "$*" >&2; exit 1; }

# Resolve a CPython 3.12 interpreter without touching the system. Order: existing python3.12
# on PATH → mise-managed → uv-managed. Prints the interpreter path on stdout. 3.12 is required
# because cu118 torch wheels stop at 3.12 and basicsr's setup.py breaks on 3.13+ (PEP 667).
PY312=""
ensure_python312() {
  local py=""
  # mise first, via its DIRECT install path — not `command -v python3.12`, which resolves to
  # a mise shim that errors ("No version is set") unless a version is activated in this dir.
  if command -v mise >/dev/null 2>&1; then
    log "Provisioning Python 3.12 via mise (user-space, no sudo)..." >&2
    mise install -y python@3.12 >&2 2>&1 || true
    local d; d="$(mise where python@3.12 2>/dev/null || true)"
    [ -n "$d" ] && [ -x "$d/bin/python3.12" ] && py="$d/bin/python3.12"
  fi
  if [ -z "$py" ] && command -v uv >/dev/null 2>&1; then
    log "Provisioning Python 3.12 via uv (user-space, no sudo)..." >&2
    uv python install 3.12 >&2 2>&1 || true
    py="$(uv python find 3.12 2>/dev/null || true)"
  fi
  # Fall back to a real (non-shim) system python3.12.
  if [ -z "$py" ]; then
    local sys; sys="$(command -v python3.12 || true)"
    [ -n "$sys" ] && py="$sys"
  fi
  # Must be a working interpreter (a dangling shim fails --version and is rejected here).
  [ -n "$py" ] && "$py" --version >/dev/null 2>&1 \
    || die "no working Python 3.12 — install mise or uv, or a system python3.12"
  PY312="$py"
}

check_prerequisites() {
  log "Checking prerequisites..."
  nvidia-smi >/dev/null 2>&1         || die "nvidia-smi not found — NVIDIA driver required"
  command -v ffmpeg  >/dev/null 2>&1 || die "ffmpeg not found"
  command -v ffprobe >/dev/null 2>&1 || die "ffprobe not found"
  command -v python3 >/dev/null 2>&1 || die "python3 not found"
  command -v git     >/dev/null 2>&1 || die "git not found"
  command -v magick  >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 \
    || die "imagemagick not found"
  log "python3 $(python3 --version), ffmpeg $(ffmpeg -version 2>&1 | awk 'NR==1{print $3}')"
}

install_video2x() {
  log "Setting up Video2X ${VIDEO2X_VERSION} in ${VIDEO2X_DIR}..."
  mkdir -p "$VIDEO2X_DIR"

  local appimage="$VIDEO2X_DIR/$VIDEO2X_APPIMAGE"
  if [ ! -f "$appimage" ]; then
    log "Downloading ${VIDEO2X_APPIMAGE}..."
    curl -L --progress-bar -o "$appimage" "$VIDEO2X_URL"
  else
    log "AppImage already present, skipping download."
  fi
  chmod +x "$appimage"

  local bin="$VIDEO2X_DIR/video2x"

  log "Extracting AppImage (ensures model paths resolve correctly)..."
  if [ ! -d "$VIDEO2X_DIR/squashfs-root" ]; then
    (cd "$VIDEO2X_DIR" && "$appimage" --appimage-extract >/dev/null 2>&1)
  fi
  local extracted="$VIDEO2X_DIR/squashfs-root/usr/bin/video2x"
  [ -f "$extracted" ] || die "Extraction failed: $extracted not found"

  # Wrapper CDs into the resource dir so model lookups (models/) succeed.
  # Rewrites relative -i/-o paths to absolute before CDing.
  cat > "$bin" <<'WRAPPER'
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_DIR="$(pwd)"
args=()
skip_next=0
for arg in "$@"; do
  if [ "$skip_next" -eq 1 ]; then
    if [[ "$arg" != /* ]]; then arg="$ORIG_DIR/$arg"; fi
    skip_next=0
  fi
  case "$arg" in -i|--input|-o|--output) skip_next=1 ;; esac
  args+=("$arg")
done
cd "$SELF_DIR/squashfs-root/usr/share/video2x"
exec "$SELF_DIR/squashfs-root/usr/bin/video2x" "${args[@]}"
WRAPPER
  chmod +x "$bin"

  log "video2x: $("$bin" --version 2>&1 | head -1)"
}

install_realesrgan() {
  log "Setting up Real-ESRGAN in ${REALESRGAN_DIR}..."

  if [ ! -d "$REALESRGAN_DIR/.git" ]; then
    log "Cloning Real-ESRGAN..."
    git clone https://github.com/xinntao/Real-ESRGAN.git "$REALESRGAN_DIR"
  else
    log "Real-ESRGAN already cloned, skipping."
  fi

  local venv_python="$REALESRGAN_DIR/venv/bin/python"
  if [ -f "$venv_python" ]; then
    log "Venv already exists, skipping Python install."
    return
  fi

  # Isolated, in-directory venv on project-local Python 3.12 (cu118 wheels + basicsr both work).
  ensure_python312
  log "Creating Python venv with $("$PY312" --version) at $REALESRGAN_DIR/venv..."
  "$PY312" -m venv "$REALESRGAN_DIR/venv"

  # Use oldest available cu118 wheel for Python 3.12 (2.2.0); basicsr patched below
  log "Installing PyTorch 2.2.0 + torchvision 0.17.0 (cu118)..."
  "$REALESRGAN_DIR/venv/bin/pip" install --quiet \
    torch==2.2.0 torchvision==0.17.0 --index-url https://download.pytorch.org/whl/cu118

  log "Installing basicsr, facexlib, gfpgan..."
  "$REALESRGAN_DIR/venv/bin/pip" install --quiet basicsr facexlib gfpgan

  log "Installing requirements.txt..."
  "$REALESRGAN_DIR/venv/bin/pip" install --quiet -r "$REALESRGAN_DIR/requirements.txt"

  log "Installing Real-ESRGAN package (editable)..."
  "$REALESRGAN_DIR/venv/bin/pip" install --quiet -e "$REALESRGAN_DIR"

  # Downgrade numpy after all deps: basicsr/torch 2.2 compiled extensions fail with numpy 2.x.
  # Pin scipy<1.13 in lockstep — newer scipy (pulled transitively by basicsr) is built for
  # numpy 2.x and uses np.long (removed in numpy 1.24–1.26), so it crashes against numpy<2.
  log "Pinning numpy<2 + scipy<1.13 (coherent numpy-1.x set)..."
  "$REALESRGAN_DIR/venv/bin/pip" install --quiet "numpy<2" "scipy<1.13"

  patch_basicsr_compatibility
}

patch_basicsr_compatibility() {
  # basicsr 1.4.2 imports torchvision.transforms.functional_tensor which was
  # removed in torchvision 0.17 (ships with torch 2.2+). Rewrite to the stable API.
  local degradations
  degradations=$(find "$REALESRGAN_DIR/venv" -path "*/basicsr/data/degradations.py" 2>/dev/null | head -1)
  [ -n "$degradations" ] || { log "basicsr degradations.py not found — skipping patch"; return; }

  if grep -q 'functional_tensor' "$degradations"; then
    log "Patching basicsr: functional_tensor → functional..."
    sed -i 's|from torchvision.transforms.functional_tensor import rgb_to_grayscale|from torchvision.transforms.functional import rgb_to_grayscale|g' \
      "$degradations"
  else
    log "basicsr already compatible, no patch needed."
  fi
}

download_model_weights() {
  log "Pre-downloading model weights..."
  local weights_dir="$REALESRGAN_DIR/weights"
  mkdir -p "$weights_dir"

  "$REALESRGAN_DIR/venv/bin/python" - "$weights_dir" <<'EOF'
import sys
from basicsr.utils.download_util import load_file_from_url
import os

weights_dir = sys.argv[1]
models = [
    ('https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth',
     'RealESRGAN_x4plus.pth'),
    ('https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth',
     'RealESRGAN_x4plus_anime_6B.pth'),
]
for url, filename in models:
    dest = os.path.join(weights_dir, filename)
    if os.path.exists(dest):
        print(f'  already present: {filename}')
    else:
        print(f'  downloading: {filename}')
        load_file_from_url(url, model_dir=weights_dir)
EOF
}

prepare_test_assets() {
  log "Preparing test assets..."
  command -v convert >/dev/null 2>&1 \
    || die "imagemagick not found — install: sudo apt install imagemagick"
  "$SCRIPT_DIR/download-test-media.sh"
}

run_initial_sweep() {
  log "Running initial upscale sweep → output/images/test-results/ ..."
  mkdir -p "$PROJECT_ROOT/output/images/test-results"
  "$SCRIPT_DIR/upscale-image.sh" \
    "$PROJECT_ROOT/test-assets/images" \
    "$PROJECT_ROOT/output/images/test-results"
  log "Sweep complete. Results in output/images/test-results/"
}

check_prerequisites
install_video2x
install_realesrgan
download_model_weights
prepare_test_assets
run_initial_sweep

log ""
log "Setup complete."
log "  video2x:    $VIDEO2X_DIR/video2x"
log "  realesrgan: $REALESRGAN_DIR"
log "  test results: output/images/test-results/"
log ""
log "To re-run the sweep after changes:  ./scripts/teardown.sh --rerun"
log "To clear test results only:         ./scripts/teardown.sh"
