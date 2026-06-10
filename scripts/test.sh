#!/usr/bin/env bash
# Upscaling pipeline test suite.
#
# Usage:
#   ./scripts/test.sh              # fast tests only (~30 s)
#   ./scripts/test.sh --integration  # + batch + video source validation (~2 min)
#
# Fast tests:  GPU checks, arg validation, dry-run format, single-image smoke.
# Integration: 2-image batch on real Wikimedia photographs, ffprobe validation
#              of real Internet Archive source clips and any pre-rendered output.
#              Run scripts/download-test-media.sh first to fetch real media.
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

assert_exit "video: invalid QUALITY → exit 1"                1 \
  scripts/upscale-video.sh -q ultra test-assets/videos/test-clip.mp4 /tmp/out.mp4

assert_exit "video: uncreateable OUTPUT dir → exit 2"        2 \
  scripts/upscale-video.sh test-assets/videos/test-clip.mp4 /proc/no-write/out.mp4

# ─── 7. VIDEO: DRY RUN (quality presets) ────────────────────────────────────────
printf '\n── Video: dry run (quality presets) ──\n'
# Default (medium): video2x realcugan at 2x
VDRY=$(scripts/upscale-video.sh -n test-assets/videos/test-clip.mp4 /tmp/out.mp4 2>/dev/null)
printf '%s' "$VDRY" | grep -q 'video2x' \
  && ok "video -q medium (default): dry run contains video2x binary" \
  || fail "video -q medium (default): dry run missing video2x — got: $VDRY"
printf '%s' "$VDRY" | grep -q 'realcugan' \
  && ok "video -q medium (default): dry run uses realcugan engine" \
  || fail "video -q medium (default): dry run missing realcugan — got: $VDRY"
printf '%s' "$VDRY" | grep -qE '\-s 2\b' \
  && ok "video -q medium (default): scale is 2x" \
  || fail "video -q medium (default): expected -s 2 in command — got: $VDRY"

# Low preset: ffmpeg lanczos, no GPU
VDRY_LOW=$(scripts/upscale-video.sh -q low -n test-assets/videos/test-clip.mp4 /tmp/out.mp4 2>/dev/null)
printf '%s' "$VDRY_LOW" | grep -q 'ffmpeg' \
  && ok "video -q low: dry run uses ffmpeg" \
  || fail "video -q low: dry run missing ffmpeg — got: $VDRY_LOW"
printf '%s' "$VDRY_LOW" | grep -q 'lanczos' \
  && ok "video -q low: dry run uses lanczos filter" \
  || fail "video -q low: dry run missing lanczos — got: $VDRY_LOW"

# High preset: video2x realesrgan at 4x
VDRY_HIGH=$(scripts/upscale-video.sh -q high -n test-assets/videos/test-clip.mp4 /tmp/out.mp4 2>/dev/null)
printf '%s' "$VDRY_HIGH" | grep -q 'video2x' \
  && ok "video -q high: dry run contains video2x binary" \
  || fail "video -q high: dry run missing video2x — got: $VDRY_HIGH"
printf '%s' "$VDRY_HIGH" | grep -qE '\-s 4\b' \
  && ok "video -q high: scale is 4x" \
  || fail "video -q high: expected -s 4 in command — got: $VDRY_HIGH"

# ─── 7b. VIDEO: LOW-QUALITY SMOKE TEST (ffmpeg, CPU, ~1 s) ──────────────────────
printf '\n── Video: low-quality smoke test (ffmpeg lanczos) ──\n'
_VID_TMPDIR=$(mktemp -d)
_VID_OUT="$_VID_TMPDIR/clip-low-2x.mp4"
if scripts/upscale-video.sh -q low test-assets/videos/test-clip.mp4 "$_VID_OUT" 2>/dev/null; then
  if [ -f "$_VID_OUT" ] && [ "$(stat -c%s "$_VID_OUT")" -gt 10000 ]; then
    VW=$(ffprobe -v error -select_streams v:0 \
          -show_entries stream=width -of csv=p=0 "$_VID_OUT" 2>/dev/null)
    VH=$(ffprobe -v error -select_streams v:0 \
          -show_entries stream=height -of csv=p=0 "$_VID_OUT" 2>/dev/null)
    [ "${VW:-0}" -eq 640 ] && [ "${VH:-0}" -eq 360 ] \
      && ok "video -q low: 320x180 → 640x360 (2x confirmed)" \
      || fail "video -q low: expected 640x360 output, got ${VW}x${VH}"
  else
    fail "video -q low: output file missing or too small"
  fi
else
  fail "video -q low: ffmpeg exited non-zero"
fi
rm -rf "$_VID_TMPDIR"

# ─── 8. INTEGRATION: IMAGE BATCH (real Wikimedia photographs) ─────────────────
# Uses canal-street-1900s.jpg (665×527) and church-building-1906.jpg (730×580)
# — real JPEG photographs with grain and compression artifacts.
# Run scripts/download-test-media.sh to fetch these files.
printf '\n── Integration: image batch (real photographs) ──\n'
REAL_IMG1="test-assets/images/canal-street-1900s.jpg"
REAL_IMG2="test-assets/images/church-building-1906.jpg"
if [ "$INTEGRATION" -eq 1 ]; then
  if [ -f "$REAL_IMG1" ] && [ -f "$REAL_IMG2" ]; then
    BATCH_IN=$(mktemp -d)
    BATCH_OUT=$(mktemp -d)
    cp "$REAL_IMG1" "$BATCH_IN/canal-street.jpg"
    cp "$REAL_IMG2" "$BATCH_IN/church-building.jpg"
    if scripts/upscale-image.sh -b "$BATCH_IN" "$BATCH_OUT" 2>/dev/null; then
      OUT_COUNT=$(find "$BATCH_OUT" \( -name '*.png' -o -name '*.jpg' \) | wc -l)
      [ "$OUT_COUNT" -eq 2 ] \
        && ok "image batch: 2 real photographs in → 2 outputs" \
        || fail "image batch: expected 2 outputs, got $OUT_COUNT"
      FIRST=$(find "$BATCH_OUT" \( -name '*.png' -o -name '*.jpg' \) | head -1)
      if [ -n "$FIRST" ]; then
        FW=$(identify -format '%w' "$FIRST" 2>/dev/null || python3 -c \
          "from PIL import Image; print(Image.open('$FIRST').width)" 2>/dev/null)
        [ "${FW:-0}" -ge 2000 ] \
          && ok "image batch: output width ${FW}px (≥4× from ~700px source)" \
          || fail "image batch: expected output width ≥2000px, got ${FW}px"
      fi
    else
      fail "image batch: inference exited non-zero"
    fi
    rm -rf "$BATCH_IN" "$BATCH_OUT"
  else
    fail "image batch: real media missing — run: scripts/download-test-media.sh"
  fi
else
  skip "image batch with real photographs (run with --integration)"
fi

# ─── 9. INTEGRATION: VALIDATE VIDEO SOURCE FILES ────────────────────────────────
# Validates the downloaded Internet Archive source clips are real video files.
printf '\n── Integration: video source validation ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  for VID_SRC in \
    "test-assets/videos/prelinger-france-1947-30s.mp4:640:480:25:35" \
    "test-assets/videos/sf-market-street-1906-30s.mp4:640:480:25:35"
  do
    IFS=: read -r vpath exp_w exp_h min_dur max_dur <<< "$VID_SRC"
    vname=$(basename "$vpath")
    if [ -f "$vpath" ] && [ "$(stat -c%s "$vpath")" -gt 100000 ]; then
      VW=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=width -of csv=p=0 "$vpath" 2>/dev/null)
      VH=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=height -of csv=p=0 "$vpath" 2>/dev/null)
      VDUR=$(ffprobe -v error -show_entries format=duration \
              -of csv=p=0 "$vpath" 2>/dev/null | cut -d. -f1)
      [ "${VW:-0}" -eq "$exp_w" ] && [ "${VH:-0}" -eq "$exp_h" ] \
        && ok "$vname: ${VW}×${VH} (expected ${exp_w}×${exp_h})" \
        || fail "$vname: expected ${exp_w}×${exp_h}, got ${VW}×${VH}"
      [ "${VDUR:-0}" -ge "$min_dur" ] && [ "${VDUR:-0}" -le "$max_dur" ] \
        && ok "$vname: duration ${VDUR}s (expected ${min_dur}–${max_dur}s)" \
        || fail "$vname: unexpected duration ${VDUR}s (expected ${min_dur}–${max_dur}s)"
    else
      fail "$vname: missing — run: scripts/download-test-media.sh"
    fi
  done
else
  skip "video source validation (run with --integration)"
fi

# ─── 10. INTEGRATION: VIDEO MEDIUM ENCODE (RealCUGAN 2×, ~2 min on 320×180) ───
# Runs -q medium on the 10 s test clip; validates output resolution and duration.
printf '\n── Integration: video medium encode (-q medium, RealCUGAN 2×) ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _VID_MED_OUT=$(mktemp /tmp/test-medium-XXXXXX.mp4)
  printf '  running video2x realcugan 2× on test-clip.mp4 — ~2 min...\n'
  if scripts/upscale-video.sh -q medium \
      test-assets/videos/test-clip.mp4 "$_VID_MED_OUT" 2>/dev/null; then
    MW=$(ffprobe -v error -select_streams v:0 \
          -show_entries stream=width -of csv=p=0 "$_VID_MED_OUT" 2>/dev/null)
    MH=$(ffprobe -v error -select_streams v:0 \
          -show_entries stream=height -of csv=p=0 "$_VID_MED_OUT" 2>/dev/null)
    MD=$(ffprobe -v error -show_entries format=duration \
          -of csv=p=0 "$_VID_MED_OUT" 2>/dev/null | cut -d. -f1)
    [ "${MW:-0}" -eq 640 ] && [ "${MH:-0}" -eq 360 ] \
      && ok "video -q medium: 320×180 → 640×360 (2× confirmed)" \
      || fail "video -q medium: expected 640×360, got ${MW}×${MH}"
    [ "${MD:-0}" -ge 9 ] && [ "${MD:-0}" -le 11 ] \
      && ok "video -q medium: duration ${MD}s (within 9–11 s)" \
      || fail "video -q medium: unexpected duration ${MD}s"
  else
    fail "video -q medium: video2x exited non-zero"
  fi
  rm -f "$_VID_MED_OUT"
else
  skip "video medium encode — RealCUGAN 2× (~2 min on 320×180 test clip; run with --integration)"
fi

# ─── SUMMARY ────────────────────────────────────────────────────────────────────
printf '\n──────────────────────────────────────\n'
printf '%d passed  %d failed  %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
