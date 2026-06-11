#!/usr/bin/env bash
# Unified entry point for media-restore tools.
# Usage: tool tui [-q PRESET] [--input DIR]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-}"; shift 2>/dev/null || true
case $CMD in
  tui)  exec python3 "$SCRIPT_DIR/scripts/tui.py" "$@" ;;
  "")   printf 'Usage: tool <command> [args]\nCommands: tui\n' >&2; exit 1 ;;
  *)    printf 'Unknown command: %s\n' "$CMD" >&2; exit 1 ;;
esac
