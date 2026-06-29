#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCALE=4
MODEL=RealESRGAN_x4plus
FORMAT=png
TILE=512
FACE_ENHANCE=0
BATCH=0
DRY_RUN=0
JSON_OUT=0
_TILE_EXPLICIT=0   # set to 1 if -t is passed; suppresses VRAM auto-tile
QUALITY_AUTO=0     # set to 1 by -q auto; tier resolved from free VRAM after the probe

REALESRGAN_DIR="${REALESRGAN_DIR:-$PROJECT_ROOT/tools/realesrgan}"
INFERENCE_SCRIPT="$REALESRGAN_DIR/inference_realesrgan.py"
VENV_PYTHON="$REALESRGAN_DIR/venv/bin/python"

usage() {
  printf 'Usage: %s [-q PRESET] [-s SCALE] [-m MODEL] [-f FORMAT] [-t TILE] [-F] [-j] [-n] [INPUT [OUTPUT]]\n' "$0"
  printf '  No args: sweeps test-assets/images/ → output/images/ (skips gt/ dirs)\n'
  printf '  INPUT   image file or directory (directories recurse, skipping gt/)\n'
  printf '  OUTPUT  output directory (default: output/images/)\n'
  printf '  -q  quality preset: low | medium | high | xhigh | auto (raw flags below override preset)\n'
  printf '        low       2x  RealESRGAN_x2plus  no-face  tile=256  fast, ~1/4 VRAM\n'
  printf '        medium    4x  RealESRGAN_x4plus  no-face  tile=512  default\n'
  printf '        high      4x  RealESRGAN_x4plus  face     tile=512  portraits/archival\n'
  printf '        xhigh 4x  RealESRGAN_x4plus  face     tile=0    max quality, full VRAM\n'
  printf '        auto      slide tier by free VRAM: <4G low, 4-8G medium, 8-12G high, >=12G xhigh\n'
  printf '  -s  upscale factor integer (default: 4)\n'
  printf '  -m  model name or /abs/path/to/model.pth (default: RealESRGAN_x4plus)\n'
  printf '  -f  output format: png | jpg | webp (default: png)\n'
  printf '  -t  tile size for VRAM management, 0=auto (default: 512)\n'
  printf '  -F  enable face enhancement via GFPGAN (opt-in)\n'
  printf '  -j  print json summary to stdout on completion\n'
  printf '  -n  dry run: print command, do not execute\n'
  printf '  -h  help\n'
  exit 0
}

while getopts ':q:s:m:f:t:Fbjnh' opt; do
  case $opt in
    q) case $OPTARG in
         low)       SCALE=2; MODEL=RealESRGAN_x2plus; FACE_ENHANCE=0; TILE=256 ;;
         medium)    SCALE=4; MODEL=RealESRGAN_x4plus; FACE_ENHANCE=0; TILE=512 ;;
         high)      SCALE=4; MODEL=RealESRGAN_x4plus; FACE_ENHANCE=1; TILE=512 ;;
         xhigh) SCALE=4; MODEL=RealESRGAN_x4plus; FACE_ENHANCE=1; TILE=0   ;;
         auto)      QUALITY_AUTO=1 ;;  # resolved from free VRAM after the probe below
         *) printf 'Unknown preset: %s  (low|medium|high|xhigh|auto)\n' "$OPTARG" >&2; exit 1 ;;
       esac ;;
    s) SCALE=$OPTARG ;;
    m) MODEL=$OPTARG ;;
    f) FORMAT=$OPTARG ;;
    t) TILE=$OPTARG; _TILE_EXPLICIT=1 ;;
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

INPUT=${1:-"$PROJECT_ROOT/test-assets/images"}
OUTPUT=${2:-"$PROJECT_ROOT/output/images"}

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

# -q auto: hardware-adaptive quality tier. VRAM is the binding constraint for inference
# feasibility, so free VRAM slides the tier low→medium→high→xhigh. Breakpoints mirror the
# VRAM→tile map below (4/8/12 GiB) so the gradient is consistent across the script. The
# tier owns scale/model/face/tile; _TILE_EXPLICIT is set so the generic remap below is skipped.
if [ "$QUALITY_AUTO" -eq 1 ]; then
  _AUTO_FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null \
    | head -1 | tr -d ' ')
  case $_AUTO_FREE in ''|*[!0-9]*) _AUTO_FREE=0 ;; esac
  if   [ "$_AUTO_FREE" -ge 12288 ]; then _TIER=xhigh;  SCALE=4; MODEL=RealESRGAN_x4plus; FACE_ENHANCE=1; TILE=0
  elif [ "$_AUTO_FREE" -ge 8192  ]; then _TIER=high;   SCALE=4; MODEL=RealESRGAN_x4plus; FACE_ENHANCE=1; TILE=512
  elif [ "$_AUTO_FREE" -ge 4096  ]; then _TIER=medium; SCALE=4; MODEL=RealESRGAN_x4plus; FACE_ENHANCE=0; TILE=512
  else                                   _TIER=low;    SCALE=2; MODEL=RealESRGAN_x2plus; FACE_ENHANCE=0; TILE=256
  fi
  _TILE_EXPLICIT=1
  printf '[auto] %s MiB free VRAM → -q %s (scale=%s model=%s face=%s tile=%s)\n' \
    "$_AUTO_FREE" "$_TIER" "$SCALE" "$MODEL" "$FACE_ENHANCE" "$TILE" >&2
fi

# VRAM probe → auto tile size (skipped if -t was explicit or DRY_RUN)
if [ "$_TILE_EXPLICIT" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  _FREE_MiB=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null \
    | head -1 | tr -d ' ')
  if [ -n "$_FREE_MiB" ] && [ "$_FREE_MiB" -gt 0 ] 2>/dev/null; then
    if   [ "$_FREE_MiB" -ge 12288 ]; then TILE=600
    elif [ "$_FREE_MiB" -ge 8192  ]; then TILE=512
    elif [ "$_FREE_MiB" -ge 6144  ]; then TILE=400
    elif [ "$_FREE_MiB" -ge 4096  ]; then TILE=300
    else                                   TILE=200
    fi
    printf '[vram] %s MiB free → tile=%s\n' "$_FREE_MiB" "$TILE" >&2
  fi
fi

[ -f "$VENV_PYTHON" ] \
  || { printf 'Python venv not found at %s\n  Run scripts/setup.sh to install\n' "$VENV_PYTHON" >&2; exit 2; }

[ -f "$INFERENCE_SCRIPT" ] \
  || { printf 'inference_realesrgan.py not found at %s\n' "$INFERENCE_SCRIPT" >&2; exit 2; }

# Validate model: either "auto", a name (no slash), or an existing file path.
# "auto" runs an ImageMagick heuristic to classify content and pick the best model.
if [ "$MODEL" = "auto" ]; then
  if [ -d "$INPUT" ]; then
    # Batch auto-select: classify first found image; apply to all (fast heuristic)
    _SAMPLE=$(find "$INPUT" ! -path '*/gt/*' \( -name '*.jpg' -o -name '*.jpeg' \
      -o -name '*.png' -o -name '*.webp' \) | head -1)
  else
    _SAMPLE="$INPUT"
  fi
  if [ -f "$_SAMPLE" ] && command -v convert >/dev/null 2>&1; then
    # Measure mean saturation (HSL) and edge density on a 256-px crop
    _SAT=$(convert "$_SAMPLE" -resize 256x256! -colorspace HSL \
      -channel Saturation -separate \
      -format "%[fx:mean*100]" info: 2>/dev/null | head -1)
    _EDGE=$(convert "$_SAMPLE" -resize 256x256! -canny 0x1+10%+30% \
      -format "%[fx:mean*1000]" info: 2>/dev/null | head -1)
    MODEL=$(printf '%s %s\n' "${_SAT:-50}" "${_EDGE:-10}" | awk '{
      sat = $1 + 0; edge = $2 + 0;
      if      (sat <  5)                     { print "RealESRGAN_x4plus" }
      else if (edge > 60 && sat < 25)        { print "RealESRGAN_x4plus_anime_6B" }
      else                                   { print "RealESRGAN_x4plus" }
    }')
    printf '[auto] content classifier: sat=%.1f edge=%.1f → model=%s\n' \
      "${_SAT:-0}" "${_EDGE:-0}" "$MODEL" >&2
  else
    MODEL=RealESRGAN_x4plus
    printf '[auto] classifier unavailable (imagemagick not found or no sample) → %s\n' "$MODEL" >&2
  fi
elif printf '%s' "$MODEL" | grep -q '/'; then
  [ -f "$MODEL" ] \
    || { printf 'Model file not found: %s\n' "$MODEL" >&2; exit 2; }
fi

# Validate input — auto-detect batch from INPUT type; -b is now a no-op kept for compat
if [ -d "$INPUT" ]; then
  BATCH=1
elif [ -f "$INPUT" ]; then
  BATCH=0
else
  printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2
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

# Count items for progress tracking; directory: recursive excluding gt/ paths
if [ "$BATCH" -eq 1 ]; then
  _TOTAL=$(find "$INPUT" ! -path '*/gt/*' ! -path '*/gt' \
    \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) | wc -l)
else
  _TOTAL=1
fi

_AUDIT_START=$SECONDS
_AUDIT_WARNINGS=""

# Sidecar path for TUI reattach (single-file mode only)
_SIDECAR=""
if [ "$BATCH" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  _STEM=$(basename "${INPUT%.*}")
  _SIDECAR="$OUTPUT/${_STEM}.${FORMAT}.progress.json"
  printf '{"status":"running","pct":0,"elapsed_s":0,"pid":%d}\n' "$$" > "$_SIDECAR"
fi

# pid lets the TUI detect a dead job: a stale "running" sidecar whose pid is gone
# is reconciled instead of being trusted forever (zombie "active" rows).
_write_sidecar_img() {
  [ -z "$_SIDECAR" ] && return 0
  printf '{"status":"%s","pct":%d,"elapsed_s":%d,"pid":%d}\n' "$1" "$2" "$SECONDS" "$$" > "$_SIDECAR"
}

# Progress bar — active when a terminal is attached; passes raw output through otherwise.
# Parses Real-ESRGAN's "Testing N name" and "Tile K/M" lines.
_progress_bar() {
  local total="$1"
  local tty=/dev/tty
  [ -w "$tty" ] 2>/dev/null || tty=/dev/stderr
  local w=40 current=0 tile_k=0 tile_m=1 pct=0 filled=0
  local bar line elapsed per remaining_secs remaining
  bar=$(printf '%*s' "$w" '' | tr ' ' '-')  # initial empty bar
  while IFS= read -r line; do
    if printf '%s' "$line" | grep -qE '^Testing [0-9]+'; then
      current=$(printf '%s' "$line" | grep -oE 'Testing [0-9]+' | grep -oE '[0-9]+')
      current=$((current + 1))
      tile_k=0; tile_m=1
      elapsed=$SECONDS
      if [ "$current" -gt 1 ] && [ "$elapsed" -gt 0 ]; then
        per=$((elapsed / (current - 1)))
        remaining_secs=$((per * (total - current + 1)))
        remaining=$(printf '%02d:%02d:%02d' \
          $((remaining_secs / 3600)) $(((remaining_secs % 3600) / 60)) $((remaining_secs % 60)))
      else
        remaining="--:--:--"
      fi
      pct=$((current * 100 / total))
      filled=$((pct * w / 100))
      bar=$(printf '%*s' "$filled" '' | tr ' ' '=')$(printf '%*s' "$((w - filled))" '' | tr ' ' '-')
      printf '\r  [%s] %d/%d  remaining: %s   ' "$bar" "$current" "$total" "$remaining" >"$tty"
    elif printf '%s' "$line" | grep -qE 'Tile [0-9]+/[0-9]+'; then
      tile_k=$(printf '%s' "$line" | grep -oE 'Tile [0-9]+' | grep -oE '[0-9]+')
      tile_m=$(printf '%s' "$line" | grep -oE '/[0-9]+$' | tr -dc '0-9')
      printf '\r  [%s] %d/%d  tile %s/%s  remaining: %s   ' \
        "$bar" "$current" "$total" "$tile_k" "$tile_m" "${remaining:---:--:--}" >"$tty"
    fi
  done
  printf '\n' >"$tty"
}

# Run inference for one source (file or directory) → output directory.
# When src is a directory, symlinks only image files into a temp dir so
# Real-ESRGAN doesn't choke on subdirectory entries in mixed dirs.
_infer() {
  local src="$1" dst="$2" total="$3" actual_src tmp=""
  if [ -d "$src" ]; then
    tmp=$(mktemp -d)
    # Resolve to an absolute path first: find emits paths as given, so a relative src
    # would create symlinks whose target dangles from the tmp dir (cv2.imread → None).
    local abs_src; abs_src="$(cd "$src" && pwd)"
    find "$abs_src" -maxdepth 1 \( -name '*.jpg' -o -name '*.jpeg' \
      -o -name '*.png' -o -name '*.webp' \) -exec ln -s {} "$tmp/" \;
    actual_src="$tmp"
  else
    actual_src="$src"
  fi
  local cmd=("$VENV_PYTHON" "$INFERENCE_SCRIPT"
    -n "$MODEL" -i "$actual_src" -o "$dst"
    --outscale "$SCALE" --tile "$TILE" --ext "$FORMAT"
  )
  [ "$FACE_ENHANCE" -eq 1 ] && cmd+=(--face_enhance)
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "${cmd[*]}"
    [ -n "$tmp" ] && rm -rf "$tmp"
    return 0
  fi
  mkdir -p "$dst"
  if [ -t 1 ] || [ -t 2 ]; then
    "${cmd[@]}" 2>&1 | _progress_bar "$total" || true
    _ec=${PIPESTATUS[0]}
    [ -n "$tmp" ] && rm -rf "$tmp"
    [ "$_ec" -eq 0 ] \
      || { _write_sidecar_img "failed" 0
           printf 'Inference failed in %s (exit %d)\n' "$src" "$_ec" >&2; exit 3; }
  else
    # Non-TTY path (used by TUI): intercept each line to update the sidecar
    # while passing output through to the capturing process (stdout/stderr).
    set +e
    "${cmd[@]}" 2>&1 | while IFS= read -r _line; do
      printf '%s\n' "$_line" >&2
      case $_line in
        Testing\ [0-9]*)
          _n=${_line#Testing }; _n=${_n%% *}; _n=$((_n + 1))
          _write_sidecar_img "running" "$((_n * 100 / (total > 0 ? total : 1)))" ;;
      esac
    done
    _ec=${PIPESTATUS[0]}
    set -e
    [ -n "$tmp" ] && rm -rf "$tmp"
    [ "$_ec" -eq 0 ] \
      || { _write_sidecar_img "failed" 0
           printf 'Inference failed — see output above\n' >&2; exit 3; }
  fi
}

if [ "$BATCH" -eq 1 ]; then
  # Recursive walk: find all subdirs with images, skip gt/ paths, mirror structure under OUTPUT
  while IFS= read -r dir; do
    imgs=$(find "$dir" -maxdepth 1 \
      \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) | wc -l)
    [ "$imgs" -eq 0 ] && continue
    rel="${dir#$INPUT}"; rel="${rel#/}"
    out_dir="$OUTPUT${rel:+/$rel}"
    printf '→ %s  (%d images)\n' "$dir" "$imgs" >&2
    _infer "$dir" "$out_dir" "$imgs"
  done < <(find "$INPUT" -type d ! -path '*/gt' ! -path '*/gt/*' | sort)
else
  _infer "$INPUT" "$OUTPUT" 1
fi

_write_sidecar_img "done" 100

if [ "$JSON_OUT" -eq 1 ]; then
  OUT_COUNT=$(find "$OUTPUT" -name "*.${FORMAT}" | wc -l)
  printf '{"input":"%s","output":"%s","model":"%s","scale":%s,"format":"%s","files_written":%s}\n' \
    "$INPUT" "$OUTPUT" "$MODEL" "$SCALE" "$FORMAT" "$OUT_COUNT"
fi

# Per-job audit manifest — written alongside output for provenance tracking.
# Captures input/output hashes, model params, timing, and any warnings.
if [ "$DRY_RUN" -eq 0 ]; then
  _AUDIT_ELAPSED=$(( SECONDS - _AUDIT_START ))
  _IN_HASH=""
  _OUT_HASH=""
  if command -v sha256sum >/dev/null 2>&1; then
    if [ -f "$INPUT" ]; then
      _IN_HASH=$(sha256sum "$INPUT" 2>/dev/null | awk '{print $1}')
    fi
    _FIRST_OUT=$(find "$OUTPUT" -name "*.${FORMAT}" | head -1)
    [ -n "$_FIRST_OUT" ] && _OUT_HASH=$(sha256sum "$_FIRST_OUT" 2>/dev/null | awk '{print $1}')
  fi
  [ "$FREE_KB" -lt 10485760 ] && _AUDIT_WARNINGS="low-disk"
  _AUDIT_PATH="$OUTPUT/${_STEM:-batch}.audit.json"
  printf '{"version":1,"media_type":"image","input":"%s","output":"%s","input_sha256":"%s","output_sha256":"%s","model":"%s","scale":%s,"tile":%s,"format":"%s","face_enhance":%s,"elapsed_s":%d,"warnings":"%s","ts":"%s"}\n' \
    "$INPUT" "$OUTPUT" "${_IN_HASH:-}" "${_OUT_HASH:-}" \
    "$MODEL" "$SCALE" "$TILE" "$FORMAT" \
    "$([ "$FACE_ENHANCE" -eq 1 ] && printf 'true' || printf 'false')" \
    "$_AUDIT_ELAPSED" "${_AUDIT_WARNINGS:-}" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$_AUDIT_PATH" 2>/dev/null || true
fi
