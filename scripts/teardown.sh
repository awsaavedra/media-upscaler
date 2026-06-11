#!/usr/bin/env bash
# Clears test-result output so the pipeline can be re-run from a clean state.
#
# Only removes output/images/test-results/ — never touches the user's own
# output/images/ or output/video/ folders.
#
# Usage:
#   ./scripts/teardown.sh           # clear test results
#   ./scripts/teardown.sh --rerun   # clear then immediately re-run the sweep
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_RESULTS="$PROJECT_ROOT/output/images/test-results"

log()  { printf '[teardown] %s\n' "$*"; }

log "Clearing $TEST_RESULTS ..."
rm -rf "$TEST_RESULTS"
mkdir -p "$TEST_RESULTS"
log "Done."

if [ "${1:-}" = "--rerun" ]; then
  log "Re-running upscale sweep → $TEST_RESULTS ..."
  "$SCRIPT_DIR/upscale-image.sh" \
    "$PROJECT_ROOT/test-assets/images" \
    "$TEST_RESULTS"
  log "Sweep complete. Results in output/images/test-results/"
fi
