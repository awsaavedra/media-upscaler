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
