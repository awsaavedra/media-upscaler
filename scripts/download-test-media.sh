#!/usr/bin/env bash
# Download real-world test media for the upscaling pipeline.
#
# Sources:
#   Internet Archive  — robots.txt: User-agent:* Disallow:/control/ /report/ (downloads allowed)
#   Wikimedia Commons — upload CDN robots.txt: Disallow:/wikipedia/commons/archive/ only
#
# All content is public domain. Files land in test-assets/ which is gitignored.
#
# Usage:
#   ./scripts/download-test-media.sh          # download images + videos
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
  # Images — Wikimedia Commons upload CDN (public domain)
  "$IMG_DIR/canal-street-1900s.jpg|https://upload.wikimedia.org/wikipedia/commons/d/de/Canal_Street_Bourbon_to_St_Chas_1900s.jpg|Canal Street New Orleans 1900s, 665×527 JPEG, real grain and JPEG compression artifacts|Public domain"
  "$IMG_DIR/church-building-1906.jpg|https://upload.wikimedia.org/wikipedia/commons/6/6f/First_Saint_Rose_of_Lima_Roman_Catholic_Church_building_with_inset_of_Father_Henry_F._Murray_1906.jpg|Church building 1906, 730×580 JPEG, historic photograph degradation|Public domain"

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
