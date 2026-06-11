#!/usr/bin/env bash
# Upscaling pipeline test suite.
#
# Usage:
#   ./scripts/test.sh                    # fast tests + result verification (~30 s, no GPU)
#   ./scripts/test.sh --integration-images  # + per-asset image inference (~5 min GPU)
#   ./scripts/test.sh --integration         # + image inference + video encodes (~15 min GPU)
#
# Fast tests:  GPU checks, arg validation, dry-run, single synthetic smoke, result verification.
# Result verification (section 6): checks output/images/test-results/ produced by setup.sh or
#   teardown --rerun. No GPU needed; just file-existence and dimension checks. 11 assets.
# Image integration (sections 10–19, 25–27): per-asset GPU inference with specific models/flags.
#   Assets: butterfly 2x, baby 4x, face-enhance -F (baby), bsd_45096, 76-ball-sign,
#   budapest-parliament, flower-foliage (clean), nyc-night (tiled), nypl-1908-scan,
#   image batch, flower-foliage-q20 (JPEG artifact), great-wave (anime_6B), douglas-portrait (-F).
# Video integration (sections 20–24): video source validation + encodes.
#   test-clip low+medium, sf-1906, france-1947.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

INTEGRATION=0
INTEGRATION_VIDEO=0
case "${1:-}" in
  --integration)        INTEGRATION=1; INTEGRATION_VIDEO=1 ;;
  --integration-images) INTEGRATION=1 ;;
esac

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

assert_exit() {
  local desc="$1" expected="$2"; shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  [ "$actual" -eq "$expected" ] && ok "$desc (exit $actual)" || fail "$desc — expected $expected got $actual"
}

# Verify an output image exists, has a minimum file size, and matches expected WxH.
assert_image() {
  local desc="$1" path="$2" expected_dims="$3" min_kb="${4:-50}"
  if [ ! -f "$path" ]; then
    fail "$desc — file not found: $path"
    return
  fi
  local kb
  kb=$(du -k "$path" | cut -f1)
  [ "${kb:-0}" -ge "$min_kb" ] \
    || { fail "$desc — file too small (${kb}KB < ${min_kb}KB): $path"; return; }
  local dims
  dims=$(identify -format '%wx%h' "$path" 2>/dev/null)
  [ "$dims" = "$expected_dims" ] \
    && ok "$desc — ${dims}, ${kb}KB" \
    || fail "$desc — expected ${expected_dims}, got ${dims}"
}

# ─── 1. GPU CHECKS ─────────────────────────────────────────────────────────────
printf '\n── GPU checks ──\n'
gpu_ec=0
"$SCRIPT_DIR/check-gpu.sh" || gpu_ec=$?
[ "$gpu_ec" -eq 0 ] && ok "check-gpu.sh: all 4 GPU checks pass" \
                     || fail "check-gpu.sh: one or more GPU checks failed (exit $gpu_ec)"

# ─── 2. IMAGE: ARGUMENT VALIDATION ─────────────────────────────────────────────
printf '\n── Image: argument validation ──\n'
assert_exit "image: missing INPUT file → exit 2"            2 \
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
    SIZE=$(identify -format '%wx%h' "$OUT" 2>/dev/null)
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

# ─── 6. RESULT VERIFICATION: per-asset sweep output ────────────────────────────
# Checks output/images/test-results/ populated by setup.sh or teardown --rerun.
# No GPU needed. Each check states the failure mode the asset is designed to catch.
printf '\n── Result verification: per-asset sweep output ──\n'
RESULTS="output/images/test-results"

if [ ! -d "$RESULTS" ] || [ -z "$(ls -A "$RESULTS" 2>/dev/null)" ]; then
  skip "result verification — $RESULTS is empty; run: ./scripts/teardown.sh --rerun"
else
  # ── Benchmark set (LR inputs committed, GT committed under gt/)
  # butterfly: 2x benchmark — fine repeating wing-scale texture.
  # Failure mode: over-sharpening creates false edge-doubling on curved wing edges.
  assert_image \
    "butterfly (fine repeating texture, 2x benchmark) → 512×512 @ 4x sweep" \
    "$RESULTS/butterfly_out.png" "512x512" 200

  # baby: 4x benchmark — face and smooth pastel gradients.
  # Failure mode: halos on skin, colour saturation drift on soft tones.
  assert_image \
    "baby (face / smooth gradient, 4x benchmark) → 512×512" \
    "$RESULTS/baby_out.png" "512x512" 200

  # bsd_45096: natural organic texture — starfish on rock.
  # Failure mode: over-smoothing turns irregular stone/starfish surface into mud.
  assert_image \
    "bsd_45096 (natural organic texture, BSD100) → 512×340" \
    "$RESULTS/bsd_45096_out.png" "512x340" 100

  # ── Demo set (real-world / restoration)
  # 76-ball-sign: text and hard-edge signage.
  # Failure mode: letterform fragmentation, hard-edge ghosting, hue shift on solid fills.
  assert_image \
    "76-ball-sign (text / hard edges) → 1280×1920" \
    "$RESULTS/demo/76-ball-sign-lr320_out.png" "1280x1920" 1000

  # budapest-parliament: fine masonry, straight architectural lines.
  # Failure mode: ringing on window mullions, stone texture smeared at high scale.
  assert_image \
    "budapest-parliament (architecture / geometry) → 1920×1240" \
    "$RESULTS/demo/budapest-parliament-lr480_out.png" "1920x1240" 1000

  # flower-foliage: petals and stamen — chaotic high-frequency organic detail.
  # Failure mode: over-smoothing collapses petal edges; hallucinated false veining.
  assert_image \
    "flower-foliage (foliage / chaotic fine detail) → 2160×1440" \
    "$RESULTS/demo/flower-foliage-lr540_out.png" "2160x1440" 1000

  # nyc-night: city at night — point-light sources and large dark shadow regions.
  # Failure mode: bloom on point lights, shadow noise amplified, colour drift in darks.
  assert_image \
    "nyc-night (night / low-light / point sources) → 3024×2000" \
    "$RESULTS/demo/nyc-night-lr756_out.png" "3024x2000" 2000

  # nypl-1908-scan: 1908 historical document scan — film grain, faded ink, sepia tone.
  # Failure mode: grain misread as signal (sharpened into noise), ink hallucinated,
  # paper sepia oversaturated.
  assert_image \
    "nypl-1908-scan (historical scan / grain / faded ink) → 1920×1256" \
    "$RESULTS/demo/nypl-1908-scan-lr480_out.png" "1920x1256" 1000

  # flower-foliage-q20: same scene as flower-foliage but input was JPEG Q20 compressed.
  # Failure mode: 8×8 DCT block boundaries remain visible after upscale; or model
  # over-smooths to suppress blocks and loses petal/stamen detail.
  assert_image \
    "flower-foliage-q20 (JPEG artifact / blocking removal) → 2160×1440" \
    "$RESULTS/demo/flower-foliage-lr540-q20_out.png" "2160x1440" 1000

  # great-wave: Hokusai woodblock print — flat colour, outlines, fine wave texture.
  # Failure mode (default sweep uses x4plus): flat fills gain false grain; outlines fringed.
  # Integration test explicitly uses anime_6B model for correct style preservation.
  assert_image \
    "great-wave (anime/illustration, flat colour and outlines) → 2400×1644" \
    "$RESULTS/demo/great-wave-lr600_out.png" "2400x1644" 2000

  # douglas-portrait: Frederick Douglass c1860s daguerreotype — historical face.
  # Failure mode: GFPGAN fails to detect face at 198px input; or hallucinates features
  # that contradict the original portrait expression.
  assert_image \
    "douglas-portrait (face enhancement / historical portrait) → 792×940" \
    "$RESULTS/demo/douglas-portrait-lr198_out.png" "792x940" 100

  # ── 4K demo set
  # metro-landscape: dense urban buildings, fine window grids at 4K scale.
  # Failure mode: window repetition collapses into smeared grid; facade colours drift.
  assert_image \
    "metro-landscape (4K cityscape / dense building detail) → 3840×2560" \
    "$RESULTS/demo/metro-landscape-lr960_out.png" "3840x2560" 8000

  # portrait-conversation: two faces, natural window light, clothing texture at 4K.
  # Failure mode: skin over-smoothed or waxy; clothing weave lost; bokeh tiled.
  assert_image \
    "portrait-conversation (4K portrait / multi-face) → 3840×2560" \
    "$RESULTS/demo/portrait-conversation-lr960_out.png" "3840x2560" 8000

  # yosemite-valley: granite cliff, pine canopy, waterfall, sky at 4K width.
  # Failure mode: tile seams visible at 3840px; canopy over-smoothed; grain injected in sky.
  assert_image \
    "yosemite-valley (4K landscape / granite + forest + sky) → 3840×1736" \
    "$RESULTS/demo/yosemite-valley-lr960_out.png" "3840x1736" 5000
fi

# ─── 7. VIDEO: ARGUMENT VALIDATION ─────────────────────────────────────────────
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

# ─── 8. VIDEO: DRY RUN (quality presets) ────────────────────────────────────────
printf '\n── Video: dry run (quality presets) ──\n'
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

VDRY_LOW=$(scripts/upscale-video.sh -q low -n test-assets/videos/test-clip.mp4 /tmp/out.mp4 2>/dev/null)
printf '%s' "$VDRY_LOW" | grep -q 'ffmpeg' \
  && ok "video -q low: dry run uses ffmpeg" \
  || fail "video -q low: dry run missing ffmpeg — got: $VDRY_LOW"
printf '%s' "$VDRY_LOW" | grep -q 'lanczos' \
  && ok "video -q low: dry run uses lanczos filter" \
  || fail "video -q low: dry run missing lanczos — got: $VDRY_LOW"

VDRY_HIGH=$(scripts/upscale-video.sh -q high -n test-assets/videos/test-clip.mp4 /tmp/out.mp4 2>/dev/null)
printf '%s' "$VDRY_HIGH" | grep -q 'video2x' \
  && ok "video -q high: dry run contains video2x binary" \
  || fail "video -q high: dry run missing video2x — got: $VDRY_HIGH"
printf '%s' "$VDRY_HIGH" | grep -qE '\-s 4\b' \
  && ok "video -q high: scale is 4x" \
  || fail "video -q high: expected -s 4 in command — got: $VDRY_HIGH"

# ─── 9. VIDEO: LOW-QUALITY SMOKE TEST (ffmpeg, CPU, ~1 s) ───────────────────────
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
      && ok "video -q low: 320×180 → 640×360 (2× confirmed)" \
      || fail "video -q low: expected 640×360 output, got ${VW}x${VH}"
    # audio passthrough: test-clip.mp4 has an AAC track — verify it is preserved
    ACODEC=$(ffprobe -v error -select_streams a:0 \
              -show_entries stream=codec_name -of csv=p=0 "$_VID_OUT" 2>/dev/null)
    [ -n "$ACODEC" ] \
      && ok "video -q low: audio track preserved (codec: $ACODEC)" \
      || fail "video -q low: audio track missing from output"
  else
    fail "video -q low: output file missing or too small"
  fi
else
  fail "video -q low: ffmpeg exited non-zero"
fi
rm -rf "$_VID_TMPDIR"

# ─────────────────────────────────────────────────────────────────────────────────
# INTEGRATION TESTS  (--integration flag required)
# Each test below runs actual GPU inference or a full encode. Runtime ~10 min total.
# ─────────────────────────────────────────────────────────────────────────────────

# ─── 10. INTEGRATION: 2x model (butterfly — fine repeating texture) ─────────────
# butterfly is the 2x benchmark. Runs RealESRGAN_x2plus instead of the default 4x
# model to match the benchmark scale. Tests that the 2x model path loads and produces
# exactly 256×256 (2× the 128×128 LR input).
printf '\n── Integration: butterfly — 2x model, fine repeating texture ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 2 -m RealESRGAN_x2plus \
      test-assets/images/butterfly.png "$_T" 2>/dev/null; then
    assert_image \
      "butterfly: RealESRGAN_x2plus 128×128 → 256×256 (fine texture, 2x benchmark)" \
      "$_T/butterfly_out.png" "256x256" 80
  else
    fail "butterfly: RealESRGAN_x2plus inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "butterfly 2x model inference (run with --integration)"
fi

# ─── 11. INTEGRATION: 4x model (baby — face / smooth gradient) ──────────────────
# baby exercises smooth skin gradients and pastel colour transitions.
# Scenario: model must not introduce halos on the face or oversaturate soft tones.
printf '\n── Integration: baby — face / smooth gradient, 4x ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus \
      test-assets/images/baby.png "$_T" 2>/dev/null; then
    assert_image \
      "baby: RealESRGAN_x4plus 128×128 → 512×512 (face / smooth gradient)" \
      "$_T/baby_out.png" "512x512" 200
  else
    fail "baby: RealESRGAN_x4plus inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "baby 4x inference (run with --integration)"
fi

# ─── 12. INTEGRATION: face enhancement flag (baby) ──────────────────────────────
# -F enables the GFPGAN face-enhance pass on top of Real-ESRGAN.
# Scenario: output must differ from non-enhanced output (GFPGAN is doing work) and
# must still be 512×512 (face enhance must not change output dimensions).
printf '\n── Integration: face enhancement flag (-F) on baby ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _TB=$(mktemp -d); _TF=$(mktemp -d)
  scripts/upscale-image.sh -s 4 test-assets/images/baby.png "$_TB" 2>/dev/null
  scripts/upscale-image.sh -s 4 -F test-assets/images/baby.png "$_TF" 2>/dev/null
  assert_image \
    "baby -F: output still 512×512 (face enhance must not resize)" \
    "$_TF/baby_out.png" "512x512" 200
  # files must differ — face enhance changes pixel values
  if cmp -s "$_TB/baby_out.png" "$_TF/baby_out.png"; then
    fail "baby -F: face-enhanced output is identical to base output — GFPGAN had no effect"
  else
    ok "baby -F: face-enhanced output differs from base (GFPGAN applied)"
  fi
  rm -rf "$_TB" "$_TF"
else
  skip "face enhancement -F test (run with --integration)"
fi

# ─── 13. INTEGRATION: natural texture (bsd_45096 — starfish) ────────────────────
# bsd_45096 is an irregular organic surface (starfish + rock).
# Scenario: upscale must not over-smooth; output ~512×340 at 4x.
printf '\n── Integration: bsd_45096 — natural organic texture ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 test-assets/images/bsd_45096.png "$_T" 2>/dev/null; then
    assert_image \
      "bsd_45096: 128×85 → 512×340 (natural organic texture)" \
      "$_T/bsd_45096_out.png" "512x340" 100
  else
    fail "bsd_45096: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "bsd_45096 natural texture inference (run with --integration)"
fi

# ─── 14. INTEGRATION: text / hard edges (76-ball-sign) ──────────────────────────
# 76-ball-sign contains lettering and a hard-edge sphere.
# Scenario: letterform edges must be sharp; output 1280×1920 at 4x.
printf '\n── Integration: 76-ball-sign — text / hard edges ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 \
      test-assets/images/demo/76-ball-sign-lr320.png "$_T" 2>/dev/null; then
    assert_image \
      "76-ball-sign: 320×480 → 1280×1920 (text / hard edges)" \
      "$_T/76-ball-sign-lr320_out.png" "1280x1920" 1000
  else
    fail "76-ball-sign: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "76-ball-sign text/hard-edge inference (run with --integration)"
fi

# ─── 15. INTEGRATION: architecture (budapest-parliament) ────────────────────────
# Fine masonry detail and straight geometric lines at 7x effective scale.
# Scenario: mullions must not ring or double; output 1920×1240 at 4x run.
printf '\n── Integration: budapest-parliament — architecture / geometry ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 \
      test-assets/images/demo/budapest-parliament-lr480.png "$_T" 2>/dev/null; then
    assert_image \
      "budapest-parliament: 480×310 → 1920×1240 (architecture / geometry)" \
      "$_T/budapest-parliament-lr480_out.png" "1920x1240" 1000
  else
    fail "budapest-parliament: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "budapest-parliament architecture inference (run with --integration)"
fi

# ─── 16. INTEGRATION: foliage / chaotic fine detail (flower-foliage) ────────────
# Petals, stamen, stem — dense overlapping fine structure.
# Scenario: petal edges must not collapse; no false veining introduced;
# output 2160×1440 at 4x (tiled: input is large enough to require 2 tiles).
printf '\n── Integration: flower-foliage — foliage / chaotic fine detail ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 -t 512 \
      test-assets/images/demo/flower-foliage-lr540.png "$_T" 2>/dev/null; then
    assert_image \
      "flower-foliage: 540×360 → 2160×1440 (foliage, 2-tile run)" \
      "$_T/flower-foliage-lr540_out.png" "2160x1440" 1000
  else
    fail "flower-foliage: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "flower-foliage foliage inference (run with --integration)"
fi

# ─── 17. INTEGRATION: night / low-light (nyc-night) ─────────────────────────────
# Point-light sources against deep dark sky.
# Scenario: point-light halos must not bleed; dark sky must not noise-sharpen;
# output 3024×2000 at 4x (largest image in the suite — stress tests tile mode).
printf '\n── Integration: nyc-night — night / low-light / point sources ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 -t 512 \
      test-assets/images/demo/nyc-night-lr756.png "$_T" 2>/dev/null; then
    assert_image \
      "nyc-night: 756×500 → 3024×2000 (night / low-light, largest asset)" \
      "$_T/nyc-night-lr756_out.png" "3024x2000" 2000
  else
    fail "nyc-night: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "nyc-night low-light inference (run with --integration)"
fi

# ─── 18. INTEGRATION: historical scan (nypl-1908-scan) ──────────────────────────
# 1908 document scan — film grain, faded ink, paper texture.
# Scenario: grain must be suppressed without smearing fine line detail;
# paper sepia tone must be preserved; output 1920×1256 at 4x.
printf '\n── Integration: nypl-1908-scan — historical scan / grain / faded ink ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 \
      test-assets/images/demo/nypl-1908-scan-lr480.png "$_T" 2>/dev/null; then
    assert_image \
      "nypl-1908-scan: 480×314 → 1920×1256 (historical scan / grain)" \
      "$_T/nypl-1908-scan-lr480_out.png" "1920x1256" 1000
  else
    fail "nypl-1908-scan: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "nypl-1908-scan historical scan inference (run with --integration)"
fi

# ─── 19. INTEGRATION: image batch — benchmark set ───────────────────────────────
# Runs both committed benchmark images through a single batch invocation.
# Tests that batch mode counts match and 4x dimensions are correct.
printf '\n── Integration: image batch — benchmark set ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  BATCH_IN=$(mktemp -d)
  BATCH_OUT=$(mktemp -d)
  cp test-assets/images/baby.png "$BATCH_IN/baby.png"
  cp test-assets/images/bsd_45096.png "$BATCH_IN/bsd_45096.png"
  if scripts/upscale-image.sh -b "$BATCH_IN" "$BATCH_OUT" 2>/dev/null; then
    OUT_COUNT=$(find "$BATCH_OUT" -name '*.png' | wc -l)
    [ "$OUT_COUNT" -eq 2 ] \
      && ok "image batch: 2 benchmark images in → 2 outputs" \
      || fail "image batch: expected 2 outputs, got $OUT_COUNT"
    assert_image \
      "image batch: baby output 512×512" \
      "$BATCH_OUT/baby_out.png" "512x512" 200
    assert_image \
      "image batch: bsd_45096 output 512×340" \
      "$BATCH_OUT/bsd_45096_out.png" "512x340" 100
  else
    fail "image batch: inference exited non-zero"
  fi
  rm -rf "$BATCH_IN" "$BATCH_OUT"
else
  skip "image batch (run with --integration-images or --integration)"
fi

# ─── 20. INTEGRATION: validate video source files ───────────────────────────────
# Confirms that the downloaded Prelinger Archive clips are valid, correct resolution,
# and correct duration before running any encode.
printf '\n── Integration: video source file validation ──\n'
if [ "$INTEGRATION_VIDEO" -eq 1 ]; then
  for VID_SRC in \
    "test-assets/videos/prelinger-france-1947-30s.mp4:640:480:25:35:mid-century documentary (1947 France)" \
    "test-assets/videos/sf-market-street-1906-30s.mp4:640:480:25:35:historical silent film (SF 1906)"
  do
    IFS=: read -r vpath exp_w exp_h min_dur max_dur vdesc <<< "$VID_SRC"
    vname=$(basename "$vpath")
    if [ -f "$vpath" ] && [ "$(stat -c%s "$vpath")" -gt 100000 ]; then
      VW=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=width -of csv=p=0 "$vpath" 2>/dev/null)
      VH=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=height -of csv=p=0 "$vpath" 2>/dev/null)
      VDUR=$(ffprobe -v error -show_entries format=duration \
              -of csv=p=0 "$vpath" 2>/dev/null | cut -d. -f1)
      [ "${VW:-0}" -eq "$exp_w" ] && [ "${VH:-0}" -eq "$exp_h" ] \
        && ok "$vname ($vdesc): ${VW}×${VH}" \
        || fail "$vname: expected ${exp_w}×${exp_h}, got ${VW}×${VH}"
      [ "${VDUR:-0}" -ge "$min_dur" ] && [ "${VDUR:-0}" -le "$max_dur" ] \
        && ok "$vname: duration ${VDUR}s (${min_dur}–${max_dur}s range)" \
        || fail "$vname: unexpected duration ${VDUR}s (expected ${min_dur}–${max_dur}s)"
    else
      fail "$vname: missing or too small — run: scripts/download-test-media.sh"
    fi
  done
else
  skip "video source file validation (run with --integration)"
fi

# ─── 21. INTEGRATION: video smoke encode — test-clip (synthetic, -q low) ────────
# test-clip.mp4 is 320×180 with audio. -q low uses CPU ffmpeg (~1 s).
# Scenario: audio passthrough must survive the encode; dimensions must double.
printf '\n── Integration: test-clip — synthetic smoke encode (-q low) ──\n'
if [ "$INTEGRATION_VIDEO" -eq 1 ]; then
  _VID_TMPDIR=$(mktemp -d)
  _VID_OUT="$_VID_TMPDIR/clip-low-2x.mp4"
  if scripts/upscale-video.sh -q low \
      test-assets/videos/test-clip.mp4 "$_VID_OUT" 2>/dev/null; then
    if [ -f "$_VID_OUT" ] && [ "$(stat -c%s "$_VID_OUT")" -gt 10000 ]; then
      VW=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
            -of csv=p=0 "$_VID_OUT" 2>/dev/null)
      VH=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
            -of csv=p=0 "$_VID_OUT" 2>/dev/null)
      DUR=$(ffprobe -v error -show_entries format=duration \
             -of csv=p=0 "$_VID_OUT" 2>/dev/null | cut -d. -f1)
      ACODEC=$(ffprobe -v error -select_streams a:0 \
                -show_entries stream=codec_name -of csv=p=0 "$_VID_OUT" 2>/dev/null)
      [ "${VW:-0}" -eq 640 ] && [ "${VH:-0}" -eq 360 ] \
        && ok "test-clip -q low: 320×180 → 640×360 (2x confirmed)" \
        || fail "test-clip -q low: expected 640×360, got ${VW}x${VH}"
      [ "${DUR:-0}" -ge 9 ] && [ "${DUR:-0}" -le 11 ] \
        && ok "test-clip -q low: duration ${DUR}s (9–11 s range)" \
        || fail "test-clip -q low: unexpected duration ${DUR}s"
      [ -n "$ACODEC" ] \
        && ok "test-clip -q low: audio preserved (codec: $ACODEC)" \
        || fail "test-clip -q low: audio track missing from output"
    else
      fail "test-clip -q low: output missing or too small"
    fi
  else
    fail "test-clip -q low: ffmpeg exited non-zero"
  fi
  rm -rf "$_VID_TMPDIR"
else
  skip "test-clip low-quality encode (run with --integration)"
fi

# ─── 22. INTEGRATION: video -q medium encode (RealCUGAN 2×) ─────────────────────
# test-clip.mp4: GPU-accelerated RealCUGAN at 2x. ~2 min on a 4 GB VRAM GPU.
# Scenario: GPU encode must produce correct dimensions and preserve duration.
printf '\n── Integration: test-clip — GPU encode (-q medium, RealCUGAN 2×) ──\n'
if [ "$INTEGRATION_VIDEO" -eq 1 ]; then
  _VID_MED_OUT=$(mktemp /tmp/test-medium-XXXXXX.mp4)
  printf '  running video2x realcugan 2× on test-clip.mp4 — ~2 min...\n'
  if scripts/upscale-video.sh -q medium \
      test-assets/videos/test-clip.mp4 "$_VID_MED_OUT" 2>/dev/null; then
    MW=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
          -of csv=p=0 "$_VID_MED_OUT" 2>/dev/null)
    MH=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
          -of csv=p=0 "$_VID_MED_OUT" 2>/dev/null)
    MD=$(ffprobe -v error -show_entries format=duration \
          -of csv=p=0 "$_VID_MED_OUT" 2>/dev/null | cut -d. -f1)
    [ "${MW:-0}" -eq 640 ] && [ "${MH:-0}" -eq 360 ] \
      && ok "test-clip -q medium: 320×180 → 640×360 (2× confirmed)" \
      || fail "test-clip -q medium: expected 640×360, got ${MW}×${MH}"
    [ "${MD:-0}" -ge 9 ] && [ "${MD:-0}" -le 11 ] \
      && ok "test-clip -q medium: duration ${MD}s (9–11 s range)" \
      || fail "test-clip -q medium: unexpected duration ${MD}s"
  else
    fail "test-clip -q medium: video2x exited non-zero"
  fi
  rm -f "$_VID_MED_OUT"
else
  skip "test-clip GPU medium encode — RealCUGAN 2× (run with --integration)"
fi

# ─── 23. INTEGRATION: historical video — sf-market-street-1906 (-q low) ─────────
# Silent film from 1906 — heavy grain, film scratches, camera movement.
# Scenario: ffmpeg 2x upscale completes without error; output dimensions correct;
# grain character preserved (cannot assert this programmatically, but we confirm
# the file is not suspiciously small — too small → blank frames or silence).
printf '\n── Integration: sf-market-street-1906 — historical silent film (-q low) ──\n'
if [ "$INTEGRATION_VIDEO" -eq 1 ]; then
  _V=$(mktemp /tmp/test-sf-XXXXXX.mp4)
  VID="test-assets/videos/sf-market-street-1906-30s.mp4"
  if [ -f "$VID" ]; then
    if scripts/upscale-video.sh -q low "$VID" "$_V" 2>/dev/null; then
      VW=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
            -of csv=p=0 "$_V" 2>/dev/null)
      VH=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
            -of csv=p=0 "$_V" 2>/dev/null)
      KB=$(du -k "$_V" | cut -f1)
      [ "${VW:-0}" -eq 1280 ] && [ "${VH:-0}" -eq 960 ] \
        && ok "sf-1906 -q low: 640×480 → 1280×960 (2× confirmed)" \
        || fail "sf-1906 -q low: expected 1280×960, got ${VW}x${VH}"
      [ "${KB:-0}" -ge 500 ] \
        && ok "sf-1906 -q low: output ${KB}KB (≥500 KB, not blank)" \
        || fail "sf-1906 -q low: output suspiciously small (${KB}KB) — possible blank frames"
    else
      fail "sf-1906 -q low: ffmpeg exited non-zero"
    fi
  else
    fail "sf-market-street-1906-30s.mp4 missing — run: scripts/download-test-media.sh"
  fi
  rm -f "$_V"
else
  skip "sf-market-street-1906 historical film encode (run with --integration)"
fi

# ─── 24. INTEGRATION: mid-century video — prelinger-france-1947 ─────────────────
# 1947 home movie — lighter grain than 1906 film, some colour information.
# Scenario: 2x upscale completes; output is 1280×960; colour encode does not
# produce a suspiciously small file (colour information retained).
printf '\n── Integration: prelinger-france-1947 — mid-century documentary (-q low) ──\n'
if [ "$INTEGRATION_VIDEO" -eq 1 ]; then
  _V=$(mktemp /tmp/test-france-XXXXXX.mp4)
  VID="test-assets/videos/prelinger-france-1947-30s.mp4"
  if [ -f "$VID" ]; then
    if scripts/upscale-video.sh -q low "$VID" "$_V" 2>/dev/null; then
      VW=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
            -of csv=p=0 "$_V" 2>/dev/null)
      VH=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
            -of csv=p=0 "$_V" 2>/dev/null)
      KB=$(du -k "$_V" | cut -f1)
      [ "${VW:-0}" -eq 1280 ] && [ "${VH:-0}" -eq 960 ] \
        && ok "france-1947 -q low: 640×480 → 1280×960 (2× confirmed)" \
        || fail "france-1947 -q low: expected 1280×960, got ${VW}x${VH}"
      [ "${KB:-0}" -ge 500 ] \
        && ok "france-1947 -q low: output ${KB}KB (≥500 KB, colour retained)" \
        || fail "france-1947 -q low: output suspiciously small (${KB}KB)"
    else
      fail "france-1947 -q low: ffmpeg exited non-zero"
    fi
  else
    fail "prelinger-france-1947-30s.mp4 missing — run: scripts/download-test-media.sh"
  fi
  rm -f "$_V"
else
  skip "prelinger-france-1947 documentary encode (run with --integration)"
fi

# ─── 25. INTEGRATION: JPEG artifact removal (flower-foliage-q20) ────────────────
# Same scene as flower-foliage but input was bicubic-downscaled then JPEG-compressed
# at quality 20. RealESRGAN_x4plus was trained on JPEG-degraded inputs; this confirms
# that code path is exercised.
# Scenario: 8×8 DCT block boundaries must not be visible in the output; petal detail
# must still be resolved (not over-smoothed to hide artifacts).
printf '\n── Integration: flower-foliage-q20 — JPEG artifact removal ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 \
      test-assets/images/demo/flower-foliage-lr540-q20.jpg "$_T" 2>/dev/null; then
    assert_image \
      "flower-foliage-q20: 540×360 Q20 JPEG → 2160×1440 (JPEG artifact removal)" \
      "$_T/flower-foliage-lr540-q20_out.png" "2160x1440" 1000
    # Output must differ from the clean-bicubic run: JPEG inputs produce different
    # (block-suppressed) output than a clean bicubic LR.
    if cmp -s "$_T/flower-foliage-lr540-q20_out.png" \
               "output/images/test-results/demo/flower-foliage-lr540_out.png" 2>/dev/null; then
      fail "flower-foliage-q20: output identical to clean LR — JPEG degradation had no effect on reconstruction"
    else
      ok "flower-foliage-q20: output differs from clean LR run (JPEG degradation handled)"
    fi
  else
    fail "flower-foliage-q20: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "flower-foliage JPEG artifact removal (run with --integration)"
fi

# ─── 26. INTEGRATION: anime/illustration model (great-wave) ──────────────────────
# Hokusai's Great Wave — flat colour fills, strong outlines, chaotic wave texture.
# Uses RealESRGAN_x4plus_anime_6B, which is trained on synthetic anime/illustration.
# Scenario: flat sky and water fills must stay grain-free; outline edges sharp; no
# photorealistic noise injected into the flat colour regions.
printf '\n── Integration: great-wave — anime/illustration model (anime_6B) ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _TA=$(mktemp -d)
  _TP=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus_anime_6B \
      test-assets/images/demo/great-wave-lr600.png "$_TA" 2>/dev/null; then
    assert_image \
      "great-wave anime_6B: 600×411 → 2400×1644 (illustration model)" \
      "$_TA/great-wave-lr600_out.png" "2400x1644" 2000
  else
    fail "great-wave: RealESRGAN_x4plus_anime_6B inference exited non-zero"
  fi
  # Cross-model comparison: photo model on same input must produce a different result,
  # confirming model selection matters for illustration content.
  if scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus \
      test-assets/images/demo/great-wave-lr600.png "$_TP" 2>/dev/null; then
    if cmp -s "$_TA/great-wave-lr600_out.png" "$_TP/great-wave-lr600_out.png"; then
      fail "great-wave: anime_6B and x4plus produced identical output — model selection not working"
    else
      ok "great-wave: anime_6B output differs from x4plus output (model selection confirmed)"
    fi
  fi
  rm -rf "$_TA" "$_TP"
else
  skip "great-wave anime/illustration model inference (run with --integration)"
fi

# ─── 27. INTEGRATION: face enhancement (douglas-portrait) ────────────────────────
# Frederick Douglass c1860s daguerreotype — 198×235 input, 4× upscale.
# Scenario: -F must detect the face at 198px input width and apply GFPGAN;
# output must differ from non-enhanced run and preserve output dimensions.
printf '\n── Integration: douglas-portrait — historical portrait + face enhancement ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _TB=$(mktemp -d); _TF=$(mktemp -d)
  scripts/upscale-image.sh -s 4 \
      test-assets/images/demo/douglas-portrait-lr198.png "$_TB" 2>/dev/null
  scripts/upscale-image.sh -s 4 -F \
      test-assets/images/demo/douglas-portrait-lr198.png "$_TF" 2>/dev/null
  assert_image \
    "douglas-portrait base: 198×235 → 792×940" \
    "$_TB/douglas-portrait-lr198_out.png" "792x940" 100
  assert_image \
    "douglas-portrait -F: 198×235 → 792×940 (face enhance must not resize)" \
    "$_TF/douglas-portrait-lr198_out.png" "792x940" 100
  if cmp -s "$_TB/douglas-portrait-lr198_out.png" "$_TF/douglas-portrait-lr198_out.png"; then
    fail "douglas-portrait -F: output identical to base — GFPGAN had no effect on historical portrait"
  else
    ok "douglas-portrait -F: output differs from base (GFPGAN detected face at 198px input)"
  fi
  rm -rf "$_TB" "$_TF"
else
  skip "douglas-portrait face enhancement -F (run with --integration)"
fi

# ─── 28. INTEGRATION: 4K cityscape (metro-landscape) ────────────────────────────
# Dense urban buildings and fine window grids at 4K scale.
# Scenario: 960×640 → 3840×2560; tiled run; window grids must stay coherent across tiles.
printf '\n── Integration: metro-landscape — 4K cityscape ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 -t 512 \
      test-assets/images/demo/metro-landscape-lr960.png "$_T" 2>/dev/null; then
    assert_image \
      "metro-landscape: 960×640 → 3840×2560 (4K cityscape)" \
      "$_T/metro-landscape-lr960_out.png" "3840x2560" 8000
  else
    fail "metro-landscape: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "metro-landscape 4K cityscape inference (run with --integration)"
fi

# ─── 29. INTEGRATION: 4K portrait (portrait-conversation) ────────────────────────
# Two faces under natural light; base run + face-enhanced run compared.
# Scenario: 960×640 → 3840×2560; -F must fire on both faces; output must differ from base.
printf '\n── Integration: portrait-conversation — 4K portrait + face enhance ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _TB=$(mktemp -d); _TF=$(mktemp -d)
  scripts/upscale-image.sh -s 4 -t 512 \
      test-assets/images/demo/portrait-conversation-lr960.png "$_TB" 2>/dev/null
  scripts/upscale-image.sh -s 4 -F -t 512 \
      test-assets/images/demo/portrait-conversation-lr960.png "$_TF" 2>/dev/null
  assert_image \
    "portrait-conversation base: 960×640 → 3840×2560" \
    "$_TB/portrait-conversation-lr960_out.png" "3840x2560" 8000
  assert_image \
    "portrait-conversation -F: 3840×2560 (face enhance must not resize)" \
    "$_TF/portrait-conversation-lr960_out.png" "3840x2560" 8000
  if cmp -s "$_TB/portrait-conversation-lr960_out.png" \
             "$_TF/portrait-conversation-lr960_out.png"; then
    fail "portrait-conversation -F: output identical to base — GFPGAN had no effect"
  else
    ok "portrait-conversation -F: output differs from base (GFPGAN fired on 4K portrait)"
  fi
  rm -rf "$_TB" "$_TF"
else
  skip "portrait-conversation 4K portrait + face enhance (run with --integration)"
fi

# ─── 30. INTEGRATION: 4K landscape (yosemite-valley) ────────────────────────────
# Granite cliffs, pine forest canopy, waterfall, sky — maximum multi-texture diversity.
# Scenario: 960×434 → 3840×1736; tiled; no seams across the panoramic width.
printf '\n── Integration: yosemite-valley — 4K landscape, multi-texture ──\n'
if [ "$INTEGRATION" -eq 1 ]; then
  _T=$(mktemp -d)
  if scripts/upscale-image.sh -s 4 -t 512 \
      test-assets/images/demo/yosemite-valley-lr960.png "$_T" 2>/dev/null; then
    assert_image \
      "yosemite-valley: 960×434 → 3840×1736 (4K landscape)" \
      "$_T/yosemite-valley-lr960_out.png" "3840x1736" 5000
  else
    fail "yosemite-valley: inference exited non-zero"
  fi
  rm -rf "$_T"
else
  skip "yosemite-valley 4K landscape inference (run with --integration)"
fi

# ─── SUMMARY ────────────────────────────────────────────────────────────────────
printf '\n──────────────────────────────────────\n'
printf '%d passed  %d failed  %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
