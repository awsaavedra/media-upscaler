#!/usr/bin/env bash
set -euo pipefail

SCALE=4
MODEL=RealESRGAN_x4plus
FORMAT=png
TILE=512
FACE_ENHANCE=0
BATCH=0
DRY_RUN=0
JSON_OUT=0

REALESRGAN_DIR="${REALESRGAN_DIR:-$HOME/.local/share/realesrgan}"
INFERENCE_SCRIPT="$REALESRGAN_DIR/inference_realesrgan.py"
VENV_PYTHON="$REALESRGAN_DIR/venv/bin/python"

usage() {
  printf 'Usage: %s [-s SCALE] [-m MODEL] [-f FORMAT] [-t TILE] [-F] [-b] [-j] [-n] INPUT OUTPUT\n' "$0"
  printf '  -s  upscale factor integer (default: 4)\n'
  printf '  -m  model name or /abs/path/to/model.pth (default: RealESRGAN_x4plus)\n'
  printf '  -f  output format: png | jpg | webp (default: png)\n'
  printf '  -t  tile size for VRAM management, 0=auto (default: 512)\n'
  printf '  -F  enable face enhancement via GFPGAN (opt-in)\n'
  printf '  -b  batch mode: INPUT is a directory of images\n'
  printf '  -j  print json summary to stdout on completion\n'
  printf '  -n  dry run: print command, do not execute\n'
  printf '  -h  help\n'
  exit 0
}

while getopts ':s:m:f:t:Fbjnh' opt; do
  case $opt in
    s) SCALE=$OPTARG ;;
    m) MODEL=$OPTARG ;;
    f) FORMAT=$OPTARG ;;
    t) TILE=$OPTARG ;;
    F) FACE_ENHANCE=1 ;;
    b) BATCH=1 ;;
    j) JSON_OUT=1 ;;
    n) DRY_RUN=1 ;;
    h) usage ;;
    :) printf 'Flag -%s requires an argument\n' "$OPTARG" >&2; exit 1 ;;
    *) printf 'Unknown flag: -%s\n' "$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

INPUT=${1:?'INPUT required — path to image or directory (use -b for directory)'}
OUTPUT=${2:?'OUTPUT required — path to output directory'}

# Validate scale
case $SCALE in
  ''|*[!0-9]*) printf 'SCALE must be a positive integer, got: %s\n' "$SCALE" >&2; exit 1 ;;
esac

# Validate tile
case $TILE in
  ''|*[!0-9]*) printf 'TILE must be a non-negative integer, got: %s\n' "$TILE" >&2; exit 1 ;;
esac

# Validate format
case $FORMAT in
  png|jpg|webp) ;;
  *) printf 'FORMAT must be png, jpg, or webp, got: %s\n' "$FORMAT" >&2; exit 1 ;;
esac

# Boundary checks — fail fast
nvidia-smi >/dev/null 2>&1 \
  || { printf 'GPU not accessible — nvidia-smi failed\n' >&2; exit 2; }

[ -f "$VENV_PYTHON" ] \
  || { printf 'Python venv not found at %s\n  Run install steps from img-implementation.md\n' "$VENV_PYTHON" >&2; exit 2; }

[ -f "$INFERENCE_SCRIPT" ] \
  || { printf 'inference_realesrgan.py not found at %s\n' "$INFERENCE_SCRIPT" >&2; exit 2; }

# Validate model: either a name (no slash) or an existing file path
if printf '%s' "$MODEL" | grep -q '/'; then
  [ -f "$MODEL" ] \
    || { printf 'Model file not found: %s\n' "$MODEL" >&2; exit 2; }
fi

# Validate input
if [ "$BATCH" -eq 1 ]; then
  [ -d "$INPUT" ] \
    || { printf 'Batch mode: INPUT must be a directory, got: %s\n' "$INPUT" >&2; exit 2; }
else
  [ -f "$INPUT" ] \
    || { printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2; }
fi

# Validate output directory is writable (create if needed)
mkdir -p "$OUTPUT" 2>/dev/null \
  || { printf 'Cannot create OUTPUT directory: %s\n' "$OUTPUT" >&2; exit 2; }
[ -w "$OUTPUT" ] \
  || { printf 'OUTPUT directory not writable: %s\n' "$OUTPUT" >&2; exit 2; }

# Disk space warning
FREE_KB=$(df -k "$OUTPUT" | awk 'NR==2{print $4}')
if [ "$FREE_KB" -lt 10485760 ]; then
  printf 'WARNING: < 10 GB free in %s\n' "$OUTPUT" >&2
fi

# Build command
CMD=("$VENV_PYTHON" "$INFERENCE_SCRIPT"
  -n "$MODEL"
  -i "$INPUT"
  -o "$OUTPUT"
  --outscale "$SCALE"
  --tile "$TILE"
  --ext "$FORMAT"
)

if [ "$FACE_ENHANCE" -eq 1 ]; then
  CMD+=(--face_enhance)
fi

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "${CMD[*]}"
  exit 0
fi

"${CMD[@]}" || { printf 'Inference failed — see output above\n' >&2; exit 3; }

if [ "$JSON_OUT" -eq 1 ]; then
  OUT_COUNT=$(find "$OUTPUT" -maxdepth 1 -name "*.${FORMAT}" | wc -l)
  printf '{"input":"%s","output":"%s","model":"%s","scale":%s,"format":"%s","files_written":%s}\n' \
    "$INPUT" "$OUTPUT" "$MODEL" "$SCALE" "$FORMAT" "$OUT_COUNT"
fi
