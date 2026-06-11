#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

QUALITY="medium"
DRY_RUN=0
JSON_OUT=0

usage() {
  printf 'Usage: %s [-q PRESET] [-j] [-n] INPUT OUTPUT\n' "$0"
  printf '\n'
  printf '  INPUT   source audio file (wav, mp3, flac, m4a, ogg)\n'
  printf '  OUTPUT  output file path\n'
  printf '\n'
  printf '  -q  quality preset (default: medium)\n'
  printf '        low     RNNoise       passthrough SR  no GPU  noise gate only, near-instant\n'
  printf '        medium  DeepFilterNet passthrough SR  opt GPU speech + background noise reduction\n'
  printf '        high    AudioSR       48 kHz output   GPU     full neural SR, ~10x realtime on 3050\n'
  printf '  -j  print json summary to stdout on completion\n'
  printf '  -n  dry run: print command, do not execute\n'
  printf '  -h  help\n'
  exit 0
}

while getopts ':q:jnh' opt; do
  case $opt in
    q) QUALITY=$OPTARG ;;
    j) JSON_OUT=1 ;;
    n) DRY_RUN=1 ;;
    h) usage ;;
    :) printf 'Flag -%s requires an argument\n' "$OPTARG" >&2; exit 1 ;;
    *) printf 'Unknown flag: -%s\n' "$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

INPUT=${1:?'INPUT required — path to source audio file'}
OUTPUT=${2:?'OUTPUT required — path for processed audio file'}

case $QUALITY in
  low|medium|high) ;;
  *) printf 'QUALITY must be low, medium, or high, got: %s\n' "$QUALITY" >&2; exit 1 ;;
esac

# Accepted source formats
case "${INPUT##*.}" in
  wav|mp3|flac|m4a|ogg|WAV|MP3|FLAC|M4A|OGG) ;;
  *) printf 'Unsupported input format: %s\n  (wav mp3 flac m4a ogg)\n' "${INPUT##*.}" >&2; exit 1 ;;
esac

[ -f "$INPUT" ] || { printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2; }

OUTDIR=$(dirname "$OUTPUT")
mkdir -p "$OUTDIR" 2>/dev/null \
  || { printf 'Cannot create OUTPUT directory: %s\n' "$OUTDIR" >&2; exit 2; }
[ -w "$OUTDIR" ] || { printf 'OUTPUT directory not writable: %s\n' "$OUTDIR" >&2; exit 2; }

# Detect audio duration (seconds) via ffprobe; used for ETA and sidecar JSON
command -v ffprobe >/dev/null 2>&1 || { printf 'ffprobe not found on PATH (install ffmpeg)\n' >&2; exit 2; }
_DUR_S=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null)
case ${_DUR_S:-} in
  ''|N/A) printf 'Cannot read duration from INPUT: %s\n' "$INPUT" >&2; exit 2 ;;
esac

# Resolve backend binary for preset
case $QUALITY in
  low)
    BACKEND=rnnoise
    BACKEND_BIN="${RNNOISE_BIN:-$PROJECT_ROOT/tools/rnnoise/rnnoise_demo}"
    ;;
  medium)
    BACKEND=deepfilternet
    BACKEND_BIN="${DEEPFILTER_BIN:-deepfilter}"
    ;;
  high)
    BACKEND=audiosr
    BACKEND_BIN="${AUDIOSR_BIN:-audiosr}"
    ;;
esac

# Boundary checks — dep presence
case $QUALITY in
  low)
    [ -x "$BACKEND_BIN" ] \
      || { printf 'rnnoise_demo not found at %s\n  Run scripts/setup.sh --audio to install\n' \
             "$BACKEND_BIN" >&2; exit 2; }
    ;;
  medium)
    command -v "$BACKEND_BIN" >/dev/null 2>&1 \
      || { printf 'deepfilter not found on PATH\n  Run scripts/setup.sh --audio to install\n' \
             >&2; exit 2; }
    ;;
  high)
    command -v "$BACKEND_BIN" >/dev/null 2>&1 \
      || { printf 'audiosr not found on PATH\n  Run scripts/setup.sh --audio to install\n' \
             >&2; exit 2; }
    nvidia-smi >/dev/null 2>&1 \
      || { printf 'GPU not accessible — nvidia-smi failed (required for audiosr high preset)\n' \
             >&2; exit 2; }
    ;;
esac

# Sidecar progress JSON path — written during inference so TUI can track + reattach
SIDECAR="${OUTPUT}.progress.json"

_sidecar_write() {
  local status="$1" pct="$2" processed_s="$3"
  local elapsed_s=$SECONDS
  local ratio=0
  if [ "$elapsed_s" -gt 0 ] && [ "${processed_s%.*}" -gt 0 ] 2>/dev/null; then
    ratio=$(awk "BEGIN{printf \"%.2f\", $processed_s / $elapsed_s}")
  fi
  printf '{"status":"%s","pct":%s,"elapsed_s":%s,"input_s":%s,"processed_s":%s,"throughput_ratio":%s}\n' \
    "$status" "$pct" "$elapsed_s" "$_DUR_S" "$processed_s" "$ratio" \
    > "$SIDECAR"
}

_sidecar_cleanup() {
  rm -f "$SIDECAR"
}

# Build command for each backend
case $QUALITY in
  low)
    # RNNoise demo: stdin PCM 16-bit 48 kHz mono → stdout cleaned PCM; wrap with sox for format I/O
    CMD=(sox "$INPUT" -t raw -r 48000 -e signed -b 16 -c 1 - \
         \| "$BACKEND_BIN" \
         \| sox -t raw -r 48000 -e signed -b 16 -c 1 - "$OUTPUT")
    ;;
  medium)
    CMD=("$BACKEND_BIN" "$INPUT" -o "$(dirname "$OUTPUT")" --output-dir "$(dirname "$OUTPUT")")
    ;;
  high)
    CMD=("$BACKEND_BIN" -i "$INPUT" -s 48000 -o "$OUTPUT")
    ;;
esac

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'backend: %s\n' "$BACKEND"
  printf 'input_duration: %s s\n' "$_DUR_S"
  printf 'sidecar: %s\n' "$SIDECAR"
  printf 'cmd: %s\n' "${CMD[*]}"
  exit 0
fi

_sidecar_write "running" 0 0

# Backends don't yet emit structured progress; run and write done/failed on exit.
# TODO: parse backend stderr to emit incremental sidecar updates once backends land.
_run_inference() {
  case $QUALITY in
    low)
      sox "$INPUT" -t raw -r 48000 -e signed -b 16 -c 1 - \
        | "$BACKEND_BIN" \
        | sox -t raw -r 48000 -e signed -b 16 -c 1 - "$OUTPUT"
      ;;
    medium)
      "$BACKEND_BIN" "$INPUT" -o "$(dirname "$OUTPUT")"
      ;;
    high)
      "$BACKEND_BIN" -i "$INPUT" -s 48000 -o "$OUTPUT"
      ;;
  esac
}

if _run_inference; then
  _sidecar_write "done" 100 "$_DUR_S"
  _sidecar_cleanup
else
  _ec=$?
  _sidecar_write "failed" 0 0
  printf 'Audio inference failed (exit %d)\n' "$_ec" >&2
  exit 3
fi

if [ "$JSON_OUT" -eq 1 ]; then
  printf '{"input":"%s","output":"%s","quality":"%s","backend":"%s","input_s":%s}\n' \
    "$INPUT" "$OUTPUT" "$QUALITY" "$BACKEND" "$_DUR_S"
fi
