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

SCALE=4
ENGINE=realesrgan
DRY_RUN=0
JSON_OUT=0

usage() {
  printf 'Usage: %s [-s SCALE] [-e ENGINE] [-j] [-n] INPUT OUTPUT\n' "$0"
  printf '  -s  upscale factor integer (default: 2)\n'
  printf '  -e  engine: realesrgan | anime4k (default: realesrgan)\n'
  printf '  -j  print json summary to stdout on completion\n'
  printf '  -n  dry run: print command, do not execute\n'
  printf '  -h  help\n'
  exit 0
}

while getopts ':s:e:jnh' opt; do
  case $opt in
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

# Validate engine value
case $ENGINE in
  realesrgan|anime4k) ;;
  *) printf 'ENGINE must be realesrgan or anime4k, got: %s\n' "$ENGINE" >&2; exit 1 ;;
esac

# Validate scale is a positive integer
case $SCALE in
  ''|*[!0-9]*) printf 'SCALE must be a positive integer, got: %s\n' "$SCALE" >&2; exit 1 ;;
esac

# Boundary checks — fail fast, surface errors early
[ -n "${VIDEO2X:-}" ] && [ -x "$VIDEO2X" ] \
  || { printf 'video2x not found — run scripts/setup.sh or set VIDEO2X env var\n' >&2; exit 2; }
command -v ffprobe  >/dev/null 2>&1 || { printf 'ffprobe not found on PATH (install ffmpeg)\n' >&2; exit 2; }
nvidia-smi          >/dev/null 2>&1 || { printf 'GPU not accessible — nvidia-smi failed\n' >&2; exit 2; }

[ -f "$INPUT" ] || { printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2; }
# Duration must be a numeric value — images report "N/A" and fail this check
_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null)
case $_DUR in
  ''|N/A) printf 'INPUT is not a valid video file: %s\n' "$INPUT" >&2; exit 2 ;;
esac

OUTDIR=$(dirname "$OUTPUT")
[ -w "$OUTDIR" ] || { printf 'OUTPUT directory not writable: %s\n' "$OUTDIR" >&2; exit 2; }

FREE_KB=$(df -k "$OUTDIR" | awk 'NR==2{print $4}')
if [ "$FREE_KB" -lt 52428800 ]; then
  printf 'WARNING: < 50 GB free in %s — large encodes may exhaust disk\n' "$OUTDIR" >&2
fi

# video2x 6.x API: map engine flag to processor + model args
case $ENGINE in
  realesrgan)
    # realesrgan-plus is the general live-action model; default is anime-optimised
    CMD=("$VIDEO2X" -i "$INPUT" -o "$OUTPUT" -s "$SCALE"
         -p realesrgan --realesrgan-model realesrgan-plus)
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

# Progress bar — active when a terminal is attached; passes raw output through otherwise.
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

if [ -t 1 ] || [ -t 2 ]; then
  "${CMD[@]}" 2>&1 | _progress_bar || true
  _ec=${PIPESTATUS[0]}
  [ "$_ec" -eq 0 ] || { printf 'video2x failed (exit %d)\n' "$_ec" >&2; exit "$_ec"; }
else
  "${CMD[@]}"
fi

if [ "$JSON_OUT" -eq 1 ]; then
  printf '{"input":"%s","output":"%s","engine":"%s","scale":%s}\n' \
    "$INPUT" "$OUTPUT" "$ENGINE" "$SCALE"
fi
