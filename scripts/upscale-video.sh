#!/usr/bin/env bash
set -euo pipefail

SCALE=2
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
command -v video2x  >/dev/null 2>&1 || { printf 'video2x not found on PATH\n' >&2; exit 2; }
command -v ffprobe  >/dev/null 2>&1 || { printf 'ffprobe not found on PATH (install ffmpeg)\n' >&2; exit 2; }
nvidia-smi          >/dev/null 2>&1 || { printf 'GPU not accessible — nvidia-smi failed\n' >&2; exit 2; }

[ -f "$INPUT" ] || { printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2; }
ffprobe -v error -i "$INPUT" >/dev/null 2>&1 \
  || { printf 'INPUT is not a valid video file: %s\n' "$INPUT" >&2; exit 2; }

OUTDIR=$(dirname "$OUTPUT")
[ -w "$OUTDIR" ] || { printf 'OUTPUT directory not writable: %s\n' "$OUTDIR" >&2; exit 2; }

FREE_KB=$(df -k "$OUTDIR" | awk 'NR==2{print $4}')
if [ "$FREE_KB" -lt 52428800 ]; then
  printf 'WARNING: < 50 GB free in %s — large encodes may exhaust disk\n' "$OUTDIR" >&2
fi

CMD=(video2x -i "$INPUT" -o "$OUTPUT" -p "$ENGINE" -s "$SCALE")

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "${CMD[*]}"
  exit 0
fi

"${CMD[@]}"

if [ "$JSON_OUT" -eq 1 ]; then
  printf '{"input":"%s","output":"%s","engine":"%s","scale":%s}\n' \
    "$INPUT" "$OUTPUT" "$ENGINE" "$SCALE"
fi
