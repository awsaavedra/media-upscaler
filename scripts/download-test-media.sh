#!/usr/bin/env bash
# Download real-world test media for the upscaling pipeline.
#
# Sources:
#   Internet Archive  — robots.txt: User-agent:* Disallow:/control/ /report/ (downloads allowed)
#   Wikimedia Commons — upload CDN robots.txt: Disallow:/wikipedia/commons/archive/ only
#
# All content is public domain or Creative Commons licensed.
# LR inputs for demo GT images are created via ImageMagick after download.
#
# Usage:
#   ./scripts/download-test-media.sh          # download images + videos + create LR inputs
#   ./scripts/download-test-media.sh --check  # verify files exist without downloading
#
# Audio sources (FreeSound) require a registered account and are not automated here.
# See readme.md for the FreeSound URLs and manual download instructions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IMG_DIR="$PROJECT_ROOT/test-assets/images"
VID_DIR="$PROJECT_ROOT/test-assets/videos"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

UA="upscaling-test-fetcher/1.0 (research; https://github.com/awsaavedra/data-restoration-vid-img-aud)"

# ── Asset manifest ─────────────────────────────────────────────────────────────
# Each entry: local_path | source_url | description | license
declare -a ASSETS=(
  # Demo GT images — Wikimedia Commons upload CDN
  # LR inputs are created from these after download (see create_lr_inputs below)
  "$IMG_DIR/demo/gt/flower-foliage.jpg|https://upload.wikimedia.org/wikipedia/commons/4/4b/Flower_stock_photo.jpg|Flower stock photo 2160×1440, foliage/petal chaos, high-freq fine detail|CC0 / public domain"
  "$IMG_DIR/demo/gt/nyc-night.jpg|https://upload.wikimedia.org/wikipedia/commons/2/22/New_York_City_at_night_HDR.jpg|New York City at night 3024×1998, point-light sources, dark shadow regions|CC BY-SA"
  "$IMG_DIR/demo/gt/great-wave.jpg|https://upload.wikimedia.org/wikipedia/commons/0/0d/Great_Wave_off_Kanagawa2.jpg|Hokusai Great Wave 8242×5640, woodblock print, flat fills and strong outlines|Public domain (pre-1828)"
  "$IMG_DIR/demo/gt/douglas-portrait.jpg|https://upload.wikimedia.org/wikipedia/commons/8/85/Frederick_Douglass_c1860s.jpg|Frederick Douglass c1860s daguerreotype 791×938, historical portrait|Public domain"
  "$IMG_DIR/demo/gt/budapest-parliament.jpg|https://upload.wikimedia.org/wikipedia/commons/f/f2/Budapest_Parlament_Building.jpg|Budapest Parliament building 3387×2185, architecture/urban, dense stone detail|CC BY-SA"
  "$IMG_DIR/demo/gt/nypl-1908-scan.jpg|https://upload.wikimedia.org/wikipedia/commons/7/74/New_York_Public_Library_1908.jpg|NYPL 1908 archival scan 5814×3800, grayscale document, film grain and halftone|Public domain"
  "$IMG_DIR/demo/gt/76-ball-sign.jpg|https://upload.wikimedia.org/wikipedia/commons/a/a1/76_ball_sign_with_signs_and_light.jpg|Union 76 ball sign 1200×1800, bold text on curved surface|CC BY-SA"
  # 4K demo set — Unsplash photos via Wikimedia Commons (CC0)
  "$IMG_DIR/demo/gt/metro-landscape.jpg|https://upload.wikimedia.org/wikipedia/commons/c/cb/Metropolitan_landscape_%28Unsplash%29.jpg|Metropolitan cityscape 5472×3648, dense urban buildings and window grids|CC0"
  "$IMG_DIR/demo/gt/portrait-conversation.jpg|https://upload.wikimedia.org/wikipedia/commons/6/6e/Young_people_in_conversation_%28Unsplash%29.jpg|Natural-light portrait two faces 5760×3840, clothing texture, bokeh background|CC0"
  "$IMG_DIR/demo/gt/yosemite-valley.jpg|https://upload.wikimedia.org/wikipedia/commons/d/d4/Yosemite_Valley_from_Tunnel_View.jpg|Yosemite Valley panorama 4169×1884, granite cliffs and pine forest|CC BY-SA 3.0"

  # Videos — Internet Archive (public domain, stream-cut to 30 s)
  # Full films are 10s–100s MB; ffmpeg streams only the needed segment
  "$VID_DIR/prelinger-france-1947-30s.mp4|FFMPEG:https://archive.org/download/dph2646mbps640x480/DP_h264_6Mbps_640x480.mp4|Prelinger Archives — Dorothy in France 1947, 640×480 home movie, real film grain|Public domain"
  "$VID_DIR/sf-market-street-1906-30s.mp4|FFMPEG:https://archive.org/download/san-francisco-market-street-in-1906-wsound-trac/San%20Francisco%20Market%20Street%20in%201906%20wsound%20trac.mp4|San Francisco Market Street 1906, 640×480 silent film, heavy grain and scratches|Public domain"
)

# ── Helpers ────────────────────────────────────────────────────────────────────
ok()   { printf '[OK]   %s\n' "$1"; }
miss() { printf '[MISS] %s\n' "$1"; }
dl()   { printf '[DL]   %s\n' "$1"; }

missing=0
downloaded=0

for entry in "${ASSETS[@]}"; do
  IFS='|' read -r dest url desc license <<< "$entry"
  name=$(basename "$dest")

  if [ -f "$dest" ] && [ "$(stat -c%s "$dest")" -gt 1000 ]; then
    ok "$name ($license)"
    continue
  fi

  miss "$name — $desc"
  missing=$((missing + 1))

  [ "$CHECK_ONLY" -eq 1 ] && continue

  dl "Fetching $name …"
  mkdir -p "$(dirname "$dest")"

  if printf '%s' "$url" | grep -q '^FFMPEG:'; then
    # Stream-cut 30 s from a large remote file — avoids downloading the full film
    src="${url#FFMPEG:}"
    ffmpeg -y -ss 0 -t 30 -i "$src" \
      -c:v libx264 -crf 23 -vf "scale=640:-2" -c:a aac -movflags +faststart \
      "$dest" 2>/dev/null \
      && ok "$name (streamed 30 s)" \
      || { printf '[ERR]  ffmpeg failed for %s\n' "$name" >&2; exit 1; }
  else
    curl -fL --user-agent "$UA" -o "$dest" "$url" \
      && ok "$name (downloaded)" \
      || { printf '[ERR]  curl failed for %s\n' "$name" >&2; exit 1; }
  fi
  downloaded=$((downloaded + 1))
done

printf '\n'
if [ "$CHECK_ONLY" -eq 1 ]; then
  [ "$missing" -eq 0 ] && printf 'All test media present.\n' \
                        || { printf '%d file(s) missing — run without --check to download.\n' "$missing"; exit 1; }
else
  [ "$downloaded" -gt 0 ] && printf '%d file(s) downloaded.\n' "$downloaded" || printf 'All files already present.\n'
fi

# ── LR input creation ─────────────────────────────────────────────────────────
# Create bicubic-downscaled LR inputs from downloaded demo GT images.
# Each entry: lr_path | gt_path | resize_geometry
declare -a LR_PAIRS=(
  "$IMG_DIR/demo/flower-foliage-lr540.png|$IMG_DIR/demo/gt/flower-foliage.jpg|540x360"
  "$IMG_DIR/demo/nyc-night-lr756.png|$IMG_DIR/demo/gt/nyc-night.jpg|756x500"
  "$IMG_DIR/demo/great-wave-lr600.png|$IMG_DIR/demo/gt/great-wave.jpg|600x"
  "$IMG_DIR/demo/budapest-parliament-lr480.png|$IMG_DIR/demo/gt/budapest-parliament.jpg|480x"
  "$IMG_DIR/demo/nypl-1908-scan-lr480.png|$IMG_DIR/demo/gt/nypl-1908-scan.jpg|480x"
  "$IMG_DIR/demo/76-ball-sign-lr320.png|$IMG_DIR/demo/gt/76-ball-sign.jpg|320x"
  # 4K demo set LRs — 960px wide, 4× bicubic; output ≥3840px wide
  "$IMG_DIR/demo/metro-landscape-lr960.png|$IMG_DIR/demo/gt/metro-landscape.jpg|960x"
  "$IMG_DIR/demo/portrait-conversation-lr960.png|$IMG_DIR/demo/gt/portrait-conversation.jpg|960x"
  "$IMG_DIR/demo/yosemite-valley-lr960.png|$IMG_DIR/demo/gt/yosemite-valley.jpg|960x"
)

[ "$CHECK_ONLY" -eq 0 ] && printf '\n── Creating LR inputs ──\n'
for pair in "${LR_PAIRS[@]}"; do
  IFS='|' read -r lr gt geom <<< "$pair"
  lr_name=$(basename "$lr")
  if [ -f "$lr" ]; then
    [ "$CHECK_ONLY" -eq 0 ] && ok "$lr_name (already present)"
    continue
  fi
  if [ ! -f "$gt" ]; then
    [ "$CHECK_ONLY" -eq 0 ] && printf '[SKIP] %s — GT not present, skipping LR creation\n' "$lr_name"
    continue
  fi
  [ "$CHECK_ONLY" -eq 0 ] && dl "Creating $lr_name from $(basename "$gt") at ${geom}…"
  command -v convert >/dev/null 2>&1 \
    || { printf '[ERR]  imagemagick convert required for LR creation\n' >&2; exit 1; }
  convert "$gt" -filter Cubic -resize "$geom" "$lr" \
    && ok "$lr_name (created)" \
    || { printf '[ERR]  convert failed for %s\n' "$lr_name" >&2; exit 1; }
done

# JPEG artifact LR — bicubic 4× downscale of flower-foliage GT then Q20 JPEG compression.
# Kept separate from LR_PAIRS because the extra -quality flag cannot go in the generic loop.
# Portrait LR — must be saved as 3-channel RGB so GFPGAN's face-paste code works.
# ImageMagick's PNG24: prefix forces 3-channel RGB output even from a grayscale source,
# and -colorspace sRGB normalises tone; avoids a system Pillow dependency (not present on
# Omarchy's Python 3.14). Width 198 (4× of the ~792px GT face crop), bicubic resample.
PORTRAIT_LR="$IMG_DIR/demo/douglas-portrait-lr198.png"
PORTRAIT_GT="$IMG_DIR/demo/gt/douglas-portrait.jpg"
if [ -f "$PORTRAIT_LR" ]; then
  [ "$CHECK_ONLY" -eq 0 ] && ok "$(basename "$PORTRAIT_LR") (already present)"
elif [ ! -f "$PORTRAIT_GT" ]; then
  [ "$CHECK_ONLY" -eq 0 ] && printf '[SKIP] %s — GT not present\n' "$(basename "$PORTRAIT_LR")"
else
  [ "$CHECK_ONLY" -eq 0 ] && dl "Creating $(basename "$PORTRAIT_LR") (RGB-forced, bicubic 4×)…"
  command -v magick >/dev/null 2>&1 \
    || { printf '[ERR]  imagemagick (magick) required for portrait LR creation\n' >&2; exit 1; }
  magick "$PORTRAIT_GT" -colorspace sRGB -filter Cubic -resize 198x "PNG24:$PORTRAIT_LR" \
    && ok "$(basename "$PORTRAIT_LR") (created)" \
    || { printf '[ERR]  magick failed for %s\n' "$(basename "$PORTRAIT_LR")" >&2; exit 1; }
fi

JPEG_LR="$IMG_DIR/demo/flower-foliage-lr540-q20.jpg"
JPEG_GT="$IMG_DIR/demo/gt/flower-foliage.jpg"
if [ -f "$JPEG_LR" ]; then
  [ "$CHECK_ONLY" -eq 0 ] && ok "$(basename "$JPEG_LR") (already present)"
elif [ ! -f "$JPEG_GT" ]; then
  [ "$CHECK_ONLY" -eq 0 ] && printf '[SKIP] %s — GT not present\n' "$(basename "$JPEG_LR")"
else
  [ "$CHECK_ONLY" -eq 0 ] && dl "Creating $(basename "$JPEG_LR") (Q20 JPEG artifact LR)…"
  command -v convert >/dev/null 2>&1 \
    || { printf '[ERR]  imagemagick convert required for LR creation\n' >&2; exit 1; }
  convert "$JPEG_GT" -filter Cubic -resize 540x360 -quality 20 "$JPEG_LR" \
    && ok "$(basename "$JPEG_LR") (created)" \
    || { printf '[ERR]  convert failed for %s\n' "$(basename "$JPEG_LR")" >&2; exit 1; }
fi

# ── Benchmark images (Set5 + BSD100) ──────────────────────────────────────────
# Real photographic benchmark inputs from jbhuang0604/SelfExSR (CC0 / research use).
#   baby.png      — Set5 img_001 LR×4  128×128  face + smooth skin gradients
#   butterfly.png — Set5 img_003 LR×2  128×128  fine repeating wing-scale texture
#   bsd_45096.png — BSD100 img_017 LR×4 120×80  natural organic landscape texture
# GT (HR) counterparts stored in gt/ for visual reference only (not checked by tests).
[ "$CHECK_ONLY" -eq 0 ] && printf '\n── Downloading benchmark images ──\n'
SELFEXSR="https://raw.githubusercontent.com/jbhuang0604/SelfExSR/master/data"
# Each entry: output_path | url | description
declare -a BENCH_IMGS=(
  "$IMG_DIR/baby.png|$SELFEXSR/Set5/image_SRF_4/img_001_SRF_4_LR.png|Set5 baby LR 128×128 (face)"
  "$IMG_DIR/gt/baby.png|$SELFEXSR/Set5/image_SRF_4/img_001_SRF_4_HR.png|Set5 baby HR 512×512"
  "$IMG_DIR/butterfly.png|$SELFEXSR/Set5/image_SRF_2/img_003_SRF_2_LR.png|Set5 butterfly LR 128×128 (texture)"
  "$IMG_DIR/gt/butterfly.png|$SELFEXSR/Set5/image_SRF_4/img_003_SRF_4_HR.png|Set5 butterfly HR 256×256"
  "$IMG_DIR/bsd_45096.png|$SELFEXSR/BSD100/image_SRF_4/img_017_SRF_4_LR.png|BSD100 img_017 LR 120×80 (organic)"
  "$IMG_DIR/gt/bsd_45096.png|$SELFEXSR/BSD100/image_SRF_4/img_017_SRF_4_HR.png|BSD100 img_017 HR 480×320"
)
for entry in "${BENCH_IMGS[@]}"; do
  IFS='|' read -r dest url desc <<< "$entry"
  relpath="${dest#$PROJECT_ROOT/}"
  if [ -f "$dest" ] && [ "$(stat -c%s "$dest")" -gt 1000 ]; then
    [ "$CHECK_ONLY" -eq 0 ] && ok "$relpath (already present)"
    continue
  fi
  miss "$relpath — $desc"
  [ "$CHECK_ONLY" -eq 1 ] && continue
  dl "Fetching $relpath…"
  mkdir -p "$(dirname "$dest")"
  curl -fL --user-agent "$UA" -o "$dest" "$url" \
    && ok "$relpath (downloaded)" \
    || { printf '[ERR]  curl failed for %s\n' "$relpath" >&2; exit 1; }
done

# ── Test video clip ────────────────────────────────────────────────────────────
# 3-second SMPTE bars at 320×180 with a 440 Hz sine audio track.
# 320×180 is used because -q low applies 2× scale → 640×360 (verified in test.sh).
TEST_CLIP="$VID_DIR/test-clip.mp4"
if [ -f "$TEST_CLIP" ]; then
  [ "$CHECK_ONLY" -eq 0 ] && ok "test-clip.mp4 (already present)"
else
  miss "test-clip.mp4"
  if [ "$CHECK_ONLY" -eq 0 ]; then
    command -v ffmpeg >/dev/null 2>&1 \
      || { printf '[ERR]  ffmpeg required for test-clip generation\n' >&2; exit 1; }
    dl "Generating test-clip.mp4 (320×180, 3 s, AAC audio)…"
    mkdir -p "$VID_DIR"
    ffmpeg -y \
      -f lavfi -i "smptebars=size=320x180:rate=25" \
      -f lavfi -i "sine=frequency=440:sample_rate=48000" \
      -t 3 -c:v libx264 -crf 23 -preset fast \
      -c:a aac -b:a 128k -shortest \
      "$TEST_CLIP" -loglevel error \
      && ok "test-clip.mp4 (generated)" \
      || { printf '[ERR]  ffmpeg failed generating test-clip.mp4\n' >&2; exit 1; }
  fi
fi
