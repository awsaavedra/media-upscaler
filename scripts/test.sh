#!/usr/bin/env bash
# Upscaling pipeline test suite.
#
# Usage:
#   ./scripts/test.sh              # fast tests only (~30 s)
#   ./scripts/test.sh --integration  # + batch + output validation (~60 s)
#
# Fast tests:  GPU checks, arg validation, dry-run format, single-image smoke.
# Integration: 2-image batch, ffprobe validation of existing video output.
# Video encode is NOT run automatically (~38 min for 10 s clip); run manually:
#   ./scripts/upscale-video.sh test-assets/videos/test-clip.mp4 output/video/test-clip-4x.mp4
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

INTEGRATION=0
[ "${1:-}" = "--integration" ] && INTEGRATION=1

PASS=0; FAIL=0; SKIP=0
_TMPDIR=""
_TINY_IMG=""

cleanup() {
  [ -n "$_TMPDIR" ]    && rm -rf "$_TMPDIR"
  [ -n "$_TINY_IMG" ]  && rm -f "$_TINY_IMG"
}
trap cleanup EXIT

# Generate a 100×100 synthetic image for smoke tests (not kept in git).
_TINY_IMG=$(mktemp /tmp/test-tiny-XXXXXX.png)
convert -size 100x100 gradient:red-blue "$_TINY_IMG" 2>/dev/null \
  || { printf 'ERROR: imagemagick convert required for smoke tests\n' >&2; exit 1; }

ok()   { printf '[PASS] %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
skip() { printf '[SKIP] %s\n' "$1"; SKIP=$((SKIP+1)); }

# Run a command; check it exits with expected code.
assert_exit() {
  local desc="$1" expected="$2"; shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  [ "$actual" -eq "$expected" ] && ok "$desc (exit $actual)" || fail "$desc — expected $expected got $actual"
}

# ─── 1. GPU CHECKS ─────────────────────────────────────────────────────────────
printf '\n── GPU checks ──\n'
gpu_ec=0
"$SCRIPT_DIR/check-gpu.sh" || gpu_ec=$?
[ "$gpu_ec" -eq 0 ] && ok "check-gpu.sh: all 4 GPU checks pass" \
                     || fail "check-gpu.sh: one or more GPU checks failed (exit $gpu_ec)"

# ─── 2. IMAGE: ARGUMENT VALIDATION ─────────────────────────────────────────────
printf '\n── Image: argument validation ──\n'
assert_exit "image: missing INPUT file → exit 2"        2 \
  scripts/upscale-image.sh no-such-file.jpg /tmp/out/

assert_exit "image: invalid SCALE (non-integer) → exit 1"  1 \
  scripts/upscale-image.sh -s abc "$_TINY_IMG" /tmp/out/

assert_exit "image: invalid FORMAT (bmp) → exit 1"         1 \
  scripts/upscale-image.sh -f bmp "$_TINY_IMG" /tmp/out/

assert_exit "image: nonexistent model path → exit 2"        2 \
  scripts/upscale-image.sh -m /no/such/model.pth "$_TINY_IMG" /tmp/out/

assert_exit "image: uncreateable OUTPUT dir → exit 2"       2 \
  scripts/upscale-image.sh "$_TINY_IMG" /proc/no-write/out/

# ─── 3. IMAGE: DRY RUN ──────────────────────────────────────────────────────────
printf '\n── Image: dry run ──\n'
DRY=$(scripts/upscale-image.sh -n "$_TINY_IMG" /tmp/out/ 2>/dev/null)
printf '%s' "$DRY" | grep -q 'inference_realesrgan.py' \
  && ok "image: dry run contains inference_realesrgan.py" \
  || fail "image: dry run missing inference_realesrgan.py — got: $DRY"
printf '%s' "$DRY" | grep -q 'RealESRGAN_x4plus' \
  && ok "image: dry run contains default model name" \
  || fail "image: dry run missing model name"

# ─── 4. IMAGE: SINGLE SMOKE TEST (tiny 100×100 → 400×400) ──────────────────────
printf '\n── Image: single inference smoke test ──\n'
_TMPDIR=$(mktemp -d)
if scripts/upscale-image.sh "$_TINY_IMG" "$_TMPDIR" 2>/dev/null; then
  OUT=$(find "$_TMPDIR" -name '*.png' | head -1)
  if [ -z "$OUT" ]; then
    fail "image: smoke test — no output PNG produced"
  else
    SIZE=$(identify -format '%wx%h' "$OUT" 2>/dev/null || python3 -c \
      "from PIL import Image; i=Image.open('$OUT'); print(f'{i.width}x{i.height}')" 2>/dev/null)
    [ "$SIZE" = "400x400" ] \
      && ok "image: 100×100 → 400×400 (4× confirmed)" \
      || fail "image: expected 400×400 output, got $SIZE"
  fi
else
  fail "image: smoke test — inference exited non-zero"
fi

# ─── 5. IMAGE: JSON OUTPUT ──────────────────────────────────────────────────────
printf '\n── Image: JSON output flag ──\n'
_TMPDIR2=$(mktemp -d)
JSON=$(scripts/upscale-image.sh -j "$_TINY_IMG" "$_TMPDIR2" 2>/dev/null)
rm -rf "$_TMPDIR2"
printf '%s' "$JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); \
  assert d['scale']==4; assert d['files_written']==1; assert 'output' in d" 2>/dev/null \
  && ok "image: -j produces valid JSON with scale=4 and files_written=1" \
  || fail "image: -j JSON invalid or missing fields — got: $JSON"

# ─── 6. VIDEO: ARGUMENT VALIDATION ─────────────────────────────────────────────
printf '\n── Video: argument validation ──\n'
assert_exit "video: missing INPUT file → exit 2"             2 \
  scripts/upscale-video.sh no-such-file.mp4 /tmp/out.mp4

assert_exit "video: image file as INPUT → exit 2"            2 \
  scripts/upscale-video.sh "$_TINY_IMG" /tmp/out.mp4

assert_exit "video: invalid ENGINE → exit 1"                 1 \
  scripts/upscale-video.sh -e ffmpeg test-assets/videos/test-clip.mp4 /tmp/out.mp4

assert_exit "video: invalid SCALE (non-integer) → exit 1"   1 \
  scripts/upscale-video.sh -s abc test-assets/videos/test-clip.mp4 /tmp/out.mp4

assert_exit "video: uncreateable OUTPUT dir → exit 2"        2 \
  scripts/upscale-video.sh test-assets/videos/test-clip.mp4 /proc/no-write/out.mp4

# ─── 7. VIDEO: DRY RUN ──────────────────────────────────────────────────────────
printf '\n── Video: dry run ──\n'
VDRY=$(scripts/upscale-video.sh -n test-assets/videos/test-clip.mp4 /tmp/out.mp4 2>/dev/null)
printf '%s' "$VDRY" | grep -q 'video2x' \
  && ok "video: dry run contains video2x binary" \
  || fail "video: dry run missing video2x — got: $VDRY"
printf '%s' "$VDRY" | grep -q 'realesrgan-plus' \
  && ok "video: dry run uses realesrgan-plus model (not anime default)" \
  || fail "video: dry run missing realesrgan-plus model"

# ─── 8. INTEGRATION: IMAGE BATCH ────────────────────────────────────────────────
printf '\n── Integration: image batch ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  BATCH_IN=$(mktemp -d)
  BATCH_OUT=$(mktemp -d)
  cp "$_TINY_IMG" "$BATCH_IN/a.png"
  cp "$_TINY_IMG" "$BATCH_IN/b.png"
  if scripts/upscale-image.sh -b "$BATCH_IN" "$BATCH_OUT" 2>/dev/null; then
    OUT_COUNT=$(find "$BATCH_OUT" -name '*.png' | wc -l)
    [ "$OUT_COUNT" -eq 2 ] \
      && ok "image batch: 2 in → 2 out" \
      || fail "image batch: expected 2 outputs, got $OUT_COUNT"
    FIRST=$(find "$BATCH_OUT" -name '*.png' | head -1)
    SZ=$(identify -format '%wx%h' "$FIRST" 2>/dev/null)
    [ "$SZ" = "400x400" ] \
      && ok "image batch: output dimensions 400×400 (4× confirmed)" \
      || fail "image batch: expected 400×400, got $SZ"
  else
    fail "image batch: inference exited non-zero"
  fi
  rm -rf "$BATCH_IN" "$BATCH_OUT"
else
  skip "image batch (run with --integration)"
fi

# ─── 9. INTEGRATION: VALIDATE VIDEO OUTPUT ──────────────────────────────────────
printf '\n── Integration: video output validation ──\n'
VIDEO_OUT="output/video/test-clip-4x.mp4"
if [ "$INTEGRATION" -eq 1 ]; then
  if [ -f "$VIDEO_OUT" ] && [ "$(stat -c%s "$VIDEO_OUT")" -gt 10000 ]; then
    W=$(ffprobe -v error -select_streams v:0 \
          -show_entries stream=width -of csv=p=0 "$VIDEO_OUT" 2>/dev/null)
    H=$(ffprobe -v error -select_streams v:0 \
          -show_entries stream=height -of csv=p=0 "$VIDEO_OUT" 2>/dev/null)
    HAS_AUDIO=$(ffprobe -v error -select_streams a:0 \
          -show_entries stream=codec_name -of csv=p=0 "$VIDEO_OUT" 2>/dev/null)
    DUR=$(ffprobe -v error -show_entries format=duration \
          -of csv=p=0 "$VIDEO_OUT" 2>/dev/null | cut -d. -f1)
    [ "$W" -eq 1280 ] && [ "$H" -eq 720 ] \
      && ok "video output: 1280×720 (4× from 320×180 source)" \
      || fail "video output: expected 1280×720, got ${W}×${H}"
    [ -n "$HAS_AUDIO" ] \
      && ok "video output: audio stream present ($HAS_AUDIO)" \
      || fail "video output: no audio stream"
    [ "$DUR" -ge 9 ] && [ "$DUR" -le 11 ] \
      && ok "video output: duration ${DUR}s (within 9–11 s of 10 s source)" \
      || fail "video output: unexpected duration ${DUR}s"
  else
    fail "video output: $VIDEO_OUT missing or too small — run the smoke test first"
  fi
else
  skip "video output validation (run with --integration)"
fi

# ─── SUMMARY ────────────────────────────────────────────────────────────────────
printf '\n──────────────────────────────────────\n'
printf '%d passed  %d failed  %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
