#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Prefer local install; allow override via env var or PATH fallback
if [ -z "${VIDEO2X:-}" ]; then
  if [ -f "$PROJECT_ROOT/tools/video2x/video2x" ]; then
    VIDEO2X="$PROJECT_ROOT/tools/video2x/video2x"
  elif command -v video2x >/dev/null 2>&1; then
    VIDEO2X=video2x
  fi
fi

QUALITY=""   # unset = medium
SCALE=""     # unset = resolved from quality preset
ENGINE=""    # unset = resolved from quality preset
DRY_RUN=0
JSON_OUT=0

usage() {
  printf 'Usage: %s [-q QUALITY] [-s SCALE] [-e ENGINE] [-j] [-n] INPUT OUTPUT\n' "$0"
  printf '\n'
  printf '  -q  quality preset — sets scale and engine together (default: medium)\n'
  printf '        low    ffmpeg lanczos 2x   CPU only  ~seconds per clip  no GPU needed\n'
  printf '        medium RealCUGAN 2x        Vulkan    ~45 min/30 s clip  recommended\n'
  printf '        high   Real-ESRGAN 4x      Vulkan    ~2 h/30 s clip    best quality\n'
  printf '\n'
  printf '  -s  override scale factor integer (overrides the -q scale)\n'
  printf '  -e  override engine: realesrgan | realcugan | anime4k (overrides the -q engine)\n'
  printf '  -j  print json summary to stdout on completion\n'
  printf '  -n  dry run: print command, do not execute\n'
  printf '  -h  help\n'
  exit 0
}

while getopts ':q:s:e:jnh' opt; do
  case $opt in
    q) QUALITY=$OPTARG ;;
    s) SCALE=$OPTARG ;;
    e) ENGINE=$OPTARG ;;
    j) JSON_OUT=1 ;;
    n) DRY_RUN=1 ;;
    h) usage ;;
    :) printf 'Flag -%s requires an argument\n' "$OPTARG" >&2; exit 1 ;;
    *) printf 'Unknown flag: -%s\n' "$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

INPUT=${1:?'INPUT required — path to source video'}
OUTPUT=${2:?'OUTPUT required — path for upscaled video'}

# Validate quality
case ${QUALITY:-medium} in
  low|medium|high) ;;
  *) printf 'QUALITY must be low, medium, or high, got: %s\n' "$QUALITY" >&2; exit 1 ;;
esac

# Apply quality preset; explicit -s / -e override the preset values
case ${QUALITY:-medium} in
  low)    SCALE=${SCALE:-2}; ENGINE=${ENGINE:-ffmpeg_scale} ;;
  medium) SCALE=${SCALE:-2}; ENGINE=${ENGINE:-realcugan} ;;
  high)   SCALE=${SCALE:-4}; ENGINE=${ENGINE:-realesrgan} ;;
esac

# Validate scale
case $SCALE in
  ''|*[!0-9]*) printf 'SCALE must be a positive integer, got: %s\n' "$SCALE" >&2; exit 1 ;;
esac

# Validate engine (ffmpeg_scale is the internal name set by -q low, not exposed via -e)
case $ENGINE in
  realesrgan|realcugan|anime4k|ffmpeg_scale) ;;
  *) printf 'ENGINE must be realesrgan, realcugan, or anime4k (or use -q low for ffmpeg scale), got: %s\n' "$ENGINE" >&2; exit 1 ;;
esac

# Boundary checks — only require GPU tools when engine needs them
command -v ffprobe >/dev/null 2>&1 || { printf 'ffprobe not found on PATH (install ffmpeg)\n' >&2; exit 2; }

if [ "$ENGINE" = "ffmpeg_scale" ]; then
  command -v ffmpeg >/dev/null 2>&1 || { printf 'ffmpeg not found on PATH\n' >&2; exit 2; }
else
  [ -n "${VIDEO2X:-}" ] && [ -x "$VIDEO2X" ] \
    || { printf 'video2x not found — run scripts/setup.sh or set VIDEO2X env var\n' >&2; exit 2; }
  nvidia-smi >/dev/null 2>&1 || { printf 'GPU not accessible — nvidia-smi failed\n' >&2; exit 2; }
fi

[ -f "$INPUT" ] || { printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2; }
# Duration must be a numeric value — images report "N/A" and fail this check
_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null)
case $_DUR in
  ''|N/A) printf 'INPUT is not a valid video file: %s\n' "$INPUT" >&2; exit 2 ;;
esac

OUTDIR=$(dirname "$OUTPUT")
mkdir -p "$OUTDIR" 2>/dev/null \
  || { printf 'Cannot create OUTPUT directory: %s\n' "$OUTDIR" >&2; exit 2; }
[ -w "$OUTDIR" ] || { printf 'OUTPUT directory not writable: %s\n' "$OUTDIR" >&2; exit 2; }

FREE_KB=$(df -k "$OUTDIR" | awk 'NR==2{print $4}')
if [ "$FREE_KB" -lt 52428800 ]; then
  printf 'WARNING: < 50 GB free in %s — large encodes may exhaust disk\n' "$OUTDIR" >&2
fi

# Build command for selected engine
case $ENGINE in
  ffmpeg_scale)
    CMD=(ffmpeg -i "$INPUT"
         -vf "scale=iw*${SCALE}:ih*${SCALE}:flags=lanczos"
         -c:v libx264 -crf 18 -preset fast -c:a copy -y "$OUTPUT")
    ;;
  realesrgan)
    # realesrgan-plus is the general live-action model; default is anime-optimised
    CMD=("$VIDEO2X" -i "$INPUT" -o "$OUTPUT" -s "$SCALE"
         -p realesrgan --realesrgan-model realesrgan-plus)
    ;;
  realcugan)
    # models-se is the general-purpose variant with 2x/3x/4x support
    CMD=("$VIDEO2X" -i "$INPUT" -o "$OUTPUT" -s "$SCALE"
         -p realcugan --realcugan-model models-se)
    ;;
  anime4k)
    # anime4k is a libplacebo shader in 6.x, not a standalone processor
    CMD=("$VIDEO2X" -i "$INPUT" -o "$OUTPUT" -s "$SCALE"
         -p libplacebo --libplacebo-shader anime4k-v4-a)
    ;;
esac

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "${CMD[*]}"
  exit 0
fi

# Sidecar for TUI reattach (AI engines only; ffmpeg_scale has its own progress)
_SIDECAR=""
if [ "$ENGINE" != "ffmpeg_scale" ]; then
  _SIDECAR="${OUTPUT}.progress.json"
  printf '{"status":"running","pct":0,"fps":"0","remaining":""}\n' > "$_SIDECAR"
fi

_write_sidecar_vid() {
  [ -z "$_SIDECAR" ] && return 0
  printf '%s\n' "$1" > "$_SIDECAR"
}

# Detect total frame count for video2x engines (used by tui-monitor.py).
# ffmpeg_scale uses ffmpeg's native progress display, so skip this for that engine.
if [ "$ENGINE" != "ffmpeg_scale" ]; then
  _FRAMES=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=nb_frames -of csv=p=0 "$INPUT" 2>/dev/null)
  # some containers don't store nb_frames; fall back to duration × fps
  if [ -z "$_FRAMES" ] || [ "$_FRAMES" = "N/A" ]; then
    _DUR_S=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null)
    _FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
        -of csv=p=0 "$INPUT" 2>/dev/null | awk -F'/' '{if($2) printf "%d", $1/$2; else print $1}')
    _FRAMES=$(python3 -c "print(round(${_DUR_S:-0} * ${_FPS:-25}))" 2>/dev/null)
  fi
fi

# Progress bar for video2x output — active when a terminal is attached.
# ffmpeg_scale uses ffmpeg's native progress display.
_progress_bar() {
  local tty=/dev/tty
  [ -w "$tty" ] 2>/dev/null || tty=/dev/stderr
  local w=40 line cur tot fps rem pct filled bar
  while IFS= read -r line; do
    # Strip ANSI escape codes and carriage returns
    line=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\r//g; s/^\[K//')
    if printf '%s' "$line" | grep -qE 'frame=[0-9]+/[0-9]+'; then
      cur=$(printf '%s' "$line" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+')
      tot=$(printf '%s' "$line" | grep -oE '/[0-9]+[^0-9]' | head -1 | tr -dc '0-9')
      fps=$(printf '%s' "$line" | grep -oE 'fps=[0-9.]+' | head -1 | cut -d= -f2)
      rem=$(printf '%s' "$line" | grep -oE 'remaining=[0-9:]+' | head -1 | cut -d= -f2)
      [ -n "$tot" ] && [ "$tot" -gt 0 ] && pct=$((cur * 100 / tot)) || pct=0
      filled=$((pct * w / 100))
      bar=$(printf '%*s' "$filled" '' | tr ' ' '=')$(printf '%*s' "$((w - filled))" '' | tr ' ' '-')
      printf '\r  [%s] %3d%%  fps: %-5s  remaining: %-9s' \
        "$bar" "$pct" "${fps:--}" "${rem:---:--:--}" >"$tty"
    else
      case $line in
        *'[info]'*|*'[warning]'*|*'[error]'*)
          printf '\n%s\n' "$line" >"$tty" ;;
      esac
    fi
  done
  printf '\n' >"$tty"
}

if [ "$ENGINE" = "ffmpeg_scale" ]; then
  "${CMD[@]}" || { printf 'ffmpeg failed (exit %d)\n' "$?" >&2; exit 3; }
elif [ -t 1 ] || [ -t 2 ]; then
  VENV_PYTHON="$PROJECT_ROOT/tools/realesrgan/venv/bin/python"
  TUI_SCRIPT="$PROJECT_ROOT/scripts/tui-monitor.py"
  if [ -f "$TUI_SCRIPT" ] && [ -x "$VENV_PYTHON" ]; then
    "${CMD[@]}" 2>&1 | "$VENV_PYTHON" "$TUI_SCRIPT" --frames "${_FRAMES:-0}" || true
    _ec=${PIPESTATUS[0]}
  else
    "${CMD[@]}" 2>&1 | _progress_bar || true
    _ec=${PIPESTATUS[0]}
  fi
  [ "$_ec" -eq 0 ] \
    || { _write_sidecar_vid '{"status":"failed"}'; printf 'video2x failed (exit %d)\n' "$_ec" >&2; exit "$_ec"; }
else
  # Non-TTY path (used by TUI): pass output through while updating sidecar.
  set +e
  "${CMD[@]}" 2>&1 | while IFS= read -r _line; do
    printf '%s\n' "$_line" >&2
    _clean=$(printf '%s' "$_line" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\r//g')
    case $_clean in
      *frame=[0-9]*/[0-9]*)
        _cur=$(printf '%s' "$_clean" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | head -1)
        _tot=$(printf '%s' "$_clean" | grep -oE '/[0-9]+' | head -1 | tr -dc '0-9')
        _fps=$(printf '%s' "$_clean" | grep -oE 'fps=[0-9.]+' | cut -d= -f2)
        _rem=$(printf '%s' "$_clean" | grep -oE 'remaining=[^ ;]+' | cut -d= -f2)
        [ -n "$_tot" ] && [ "$_tot" -gt 0 ] && _pct=$((_cur * 100 / _tot)) || _pct=0
        printf '{"status":"running","pct":%d,"fps":"%s","remaining":"%s"}\n' \
          "$_pct" "${_fps:-0}" "${_rem:-}" > "$_SIDECAR" ;;
    esac
  done
  _ec=${PIPESTATUS[0]}
  set -e
  [ "$_ec" -eq 0 ] \
    || { _write_sidecar_vid '{"status":"failed"}'; printf 'video2x failed (exit %d)\n' "$_ec" >&2; exit "$_ec"; }
fi

_write_sidecar_vid '{"status":"done","pct":100}'

if [ "$JSON_OUT" -eq 1 ]; then
  printf '{"input":"%s","output":"%s","quality":"%s","engine":"%s","scale":%s}\n' \
    "$INPUT" "$OUTPUT" "${QUALITY:-medium}" "$ENGINE" "$SCALE"
fi
