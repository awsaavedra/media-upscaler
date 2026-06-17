#!/usr/bin/env bash
# Unified entry point for media-restore tools.
#
# Usage:
#   tool tui [-q PRESET] [--input DIR]
#   tool upscale image  [flags] INPUT OUTPUT
#   tool upscale video  [flags] INPUT OUTPUT
#   tool upscale audio  [flags] INPUT OUTPUT
#   tool upscale        (shows subcommand help)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-}"; shift 2>/dev/null || true

case $CMD in
  tui)
    exec python3 "$SCRIPT_DIR/scripts/tui.py" "$@"
    ;;

  upscale)
    MEDIA="${1:-}"; shift 2>/dev/null || true
    case $MEDIA in
      image)  exec bash "$SCRIPT_DIR/scripts/upscale-image.sh" "$@" ;;
      video)  exec bash "$SCRIPT_DIR/scripts/upscale-video.sh" "$@" ;;
      audio)  exec bash "$SCRIPT_DIR/scripts/upscale-audio.sh" "$@" ;;
      "")
        printf 'Usage: tool upscale <image|video|audio> [flags] INPUT OUTPUT\n' >&2
        printf '\n' >&2
        printf '  tool upscale image  [-q low|medium|high|ultrahigh] [-s SCALE] [-m MODEL]\n' >&2
        printf '                      [-f FORMAT] [-t TILE] [-F] [-j] [-n] INPUT OUTPUT\n' >&2
        printf '  tool upscale video  [-q fast|low|medium|high|ultrahigh] [-s SCALE] [-e ENGINE]\n' >&2
        printf '                      [-D] [-I 2x] [-T conservative|balanced|performance]\n' >&2
        printf '                      [-C SECS] [-r] [-c] [-j] [-n] INPUT OUTPUT\n' >&2
        printf '  tool upscale audio  [-q low|medium|high] [-j] [-n] INPUT OUTPUT\n' >&2
        exit 1
        ;;
      *)
        printf 'Unknown upscale subcommand: %s  (image|video|audio)\n' "$MEDIA" >&2
        exit 1
        ;;
    esac
    ;;

  "")
    printf 'Usage: tool <command> [args]\n' >&2
    printf 'Commands:\n' >&2
    printf '  tui              Interactive job queue TUI\n' >&2
    printf '  upscale          Upscale image|video|audio\n' >&2
    exit 1
    ;;

  *)
    printf 'Unknown command: %s\n' "$CMD" >&2
    exit 1
    ;;
esac
