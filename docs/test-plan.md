# Test Plan — Images and Video

This document is the authoritative record of the test asset suite: what is committed, what each asset covers, the exact invocation parameters for each, and where to fetch assets that are not committed.

Large originals (GT sources, raw downloads) are **not stored in the repo** — only the LR inputs and the demo GT files are committed. The sections below provide exact download commands for anything that needs to be fetched.

---

## Directory layout

```
test-assets/
  images/
    *.png             ← LR inputs (benchmark set: Set5, BSD100)
    gt/               ← GT originals (benchmark set)
    demo/
      *-lr*.png       ← LR inputs (demo / real-world set)
      gt/             ← GT originals (demo set, committed)
  videos/
    *.mp4             ← test clips (committed; no GT pair)
```

---

## Image benchmark set (PSNR-comparable)

These pairs have a clean or near-clean integer scale factor. Use them for quantitative quality checks (PSNR / SSIM) because the LR was synthetically downscaled from the GT by bicubic interpolation.

### butterfly — fine repeating texture

| Field | Value |
|---|---|
| LR | `test-assets/images/butterfly.png` — 128×128 |
| GT | `test-assets/images/gt/butterfly.png` — 256×256 |
| Scale | 2× |
| Source | Set5 SR benchmark (public domain research dataset) |
| Category | Fine repetitive texture (wing scales) |
| What it stresses | High-frequency fine detail reconstruction; aliasing on curved edges |

**Invocation**
```bash
./scripts/upscale-image.sh -s 2 -m RealESRGAN_x2plus -t 512 \
  test-assets/images/butterfly.png /tmp/out/
```

**Pass criteria**
- Output dims: 256×256 (2× each axis)
- Visual: wing scales sharp, no checkerboard or ringing artifacts
- Quantitative: PSNR ≥ 28 dB vs GT (typical RealESRGAN_x2plus baseline on Set5)

---

### baby — face / smooth gradient

| Field | Value |
|---|---|
| LR | `test-assets/images/baby.png` — 128×128 |
| GT | `test-assets/images/gt/baby.png` — 512×512 |
| Scale | 4× |
| Source | Set5 SR benchmark |
| Category | Face, smooth gradients, soft color transitions |
| What it stresses | Over-sharpening on smooth skin; color fidelity on pastel tones |

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/baby.png /tmp/out/
```

**Pass criteria**
- Output dims: 512×512
- Visual: no halos on skin, smooth tonal gradients preserved
- Quantitative: PSNR ≥ 32 dB vs GT (typical RealESRGAN_x4plus baseline on Set5)

---

### bsd_45096 — natural organic texture (starfish)

| Field | Value |
|---|---|
| LR | `test-assets/images/bsd_45096.png` — 128×85 |
| GT | `test-assets/images/gt/bsd_45096.png` — 481×321 |
| Scale | ~3.75× (treat as 4× run; compare qualitatively or after GT crop) |
| Source | BSD100 SR benchmark |
| Category | Natural outdoor texture — irregular organic surface |
| What it stresses | Non-repeating natural texture; mixed smooth/rough transitions |

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/bsd_45096.png /tmp/out/
```

**Pass criteria**
- Output dims: ~512×340
- Visual: rock and starfish textures distinct, no mud or over-smoothing
- Quantitative: compare center crop only (GT is slightly non-integer scale); PSNR is informational

---

## Image demo set (real-world / restoration)

These images are not synthetically downscaled at a clean ratio — they are genuine low-resolution or degraded sources paired with an original that represents the target quality. Comparison is qualitative. GT files for these are committed because they are small enough (< 8 MB each).

### budapest-parliament — architecture / hard geometry

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/budapest-parliament-lr480.png` — 480×310 |
| GT | `test-assets/images/demo/gt/budapest-parliament.jpg` — 3387×2185 |
| Effective scale | ~7× (run at 4×; compare sub-region visually against GT) |
| License | CC BY 2.0 — Wikimedia Commons |
| Category | Architecture, fine stone detail, repeating masonry patterns |
| What it stresses | Hard straight edges without ringing; fine carved stone detail at scale |

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/demo/budapest-parliament-lr480.png /tmp/out/
```

**Pass criteria (qualitative)**
- Window mullions and masonry joints sharp without doubling
- Stone facade texture legible at output resolution
- No color saturation drift on the grey stone

---

### 76-ball-sign — text / hard edges / signage

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/76-ball-sign-lr320.png` — 320×480 |
| GT | `test-assets/images/demo/gt/76-ball-sign.jpg` — 1200×1800 |
| Effective scale | ~3.75× |
| License | CC BY-SA — Wikimedia Commons |
| Category | Text, lettering, hard straight and curved edges |
| What it stresses | Letterform fidelity; hard edges without ghosting; color accuracy on solid fills |

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/demo/76-ball-sign-lr320.png /tmp/out/
```

**Pass criteria (qualitative)**
- Digit "76" legible and sharp without serif fragmentation
- Orange sphere gradient smooth, no banding
- Background sky blue unchanged in hue

---

### nypl-1908-scan — historical scan / noise / faded detail

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/nypl-1908-scan-lr480.png` — 480×314 |
| GT | `test-assets/images/demo/gt/nypl-1908-scan.jpg` — 5814×3800 |
| Effective scale | ~12× (run at 4×; GT is the original NYPL scan) |
| License | Public domain — NYPL Digital Collections |
| Category | Historical document, film grain, faded ink, paper texture |
| What it stresses | Noise/grain handling; recovering faded ink without hallucinating content |

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/demo/nypl-1908-scan-lr480.png /tmp/out/
```

**Pass criteria (qualitative)**
- Text (if any) sharper but not redesigned
- Film grain suppressed without smearing fine line detail
- Paper tone preserved; no oversaturation of sepia tones

---

## Video test set

No GT pairs for video — all assessments are qualitative / frame-level visual inspection. Run frame extraction (`ffmpeg -i clip.mp4 frames/%04d.png`) on output and input and compare visually.

### test-clip.mp4 — smoke test

| Field | Value |
|---|---|
| Path | `test-assets/videos/test-clip.mp4` |
| Specs | 320×180, 24 fps, 10 s, H.264 + AAC, ~200 KB |
| Category | Synthetic — fast smoke test only |
| What it stresses | Basic pipeline invocation; audio passthrough; small VRAM footprint |

**Invocation**
```bash
./scripts/upscale-video.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/videos/test-clip.mp4 /tmp/out/test-clip-4x.mp4
```

**Pass criteria**
- Output exists, non-zero bytes, valid MP4
- Output resolution: 1280×720
- Audio track present and unchanged
- Runtime: completes without OOM in under 3 min on a 4 GB VRAM GPU

---

### sf-market-street-1906-30s.mp4 — historical footage / motion

| Field | Value |
|---|---|
| Path | `test-assets/videos/sf-market-street-1906-30s.mp4` |
| Specs | 640×480, 25 fps, 30 s, H.264, ~2.4 MB |
| License | Public domain — Prelinger Archives via Internet Archive |
| Category | Historical archival film, heavy grain, camera movement, street scene |
| What it stresses | Temporal consistency frame-to-frame; grain suppression vs detail; moving subjects |

**Invocation**
```bash
./scripts/upscale-video.sh -s 2 -m RealESRGAN_x2plus -t 512 \
  test-assets/videos/sf-market-street-1906-30s.mp4 /tmp/out/sf-1906-2x.mp4
```

**Pass criteria (qualitative)**
- No temporal flicker between frames (compare frame N vs N+1 diff)
- Street cobblestones and building edges sharper without ghosting on moving people
- Film grain reduced but not fully eliminated (keep film character)

---

### prelinger-france-1947-30s.mp4 — mid-century color / motion

| Field | Value |
|---|---|
| Path | `test-assets/videos/prelinger-france-1947-30s.mp4` |
| Specs | 640×480, 24 fps, 30 s, H.264, ~2.7 MB |
| License | Public domain — Prelinger Archives via Internet Archive |
| Category | Mid-century documentary, lighter grain, some color degradation |
| What it stresses | Color accuracy under upscale; moderate grain; mixed indoor/outdoor scenes |

**Invocation**
```bash
./scripts/upscale-video.sh -s 2 -m RealESRGAN_x2plus -t 512 \
  test-assets/videos/prelinger-france-1947-30s.mp4 /tmp/out/france-1947-2x.mp4
```

**Pass criteria (qualitative)**
- Color hues not shifted (compare histogram of input vs output)
- Text on screen (if any) legible at output resolution
- No temporal banding on slow-pan shots

---

## Image demo set (continued) — recently added

### flower-foliage — foliage / chaotic fine detail

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/flower-foliage-lr540.png` — 540×360 |
| GT | `test-assets/images/demo/gt/flower-foliage.jpg` — 2160×1440 |
| Scale | 4× |
| License | CC0 / public domain — Wikimedia Commons |
| Category | Petals, stem, stamen — chaotic organic fine detail |
| What it stresses | Over-smoothing chaos; hallucinated veining; petal edge fragmentation |

**Fetch GT (idempotent):**
```bash
[ -f test-assets/images/demo/gt/flower-foliage.jpg ] || \
  curl -L "https://upload.wikimedia.org/wikipedia/commons/4/4b/Flower_stock_photo.jpg" \
    -o test-assets/images/demo/gt/flower-foliage.jpg
[ -f test-assets/images/demo/flower-foliage-lr540.png ] || \
  convert test-assets/images/demo/gt/flower-foliage.jpg \
    -filter Cubic -resize 540x360 test-assets/images/demo/flower-foliage-lr540.png
```

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/demo/flower-foliage-lr540.png /tmp/out/
```

**Pass criteria (qualitative)**
- Petal edges sharp without false veining inserted
- Stamen center texture not smeared into uniform blobs
- Green stem edges clean and not haloed

---

### nyc-night — night / low-light / point sources

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/nyc-night-lr756.png` — 756×500 |
| GT | `test-assets/images/demo/gt/nyc-night.jpg` — 3024×1998 |
| Scale | 4× |
| License | CC BY-SA — Wikimedia Commons |
| Category | Night cityscape, point-light sources, dark shadow regions |
| What it stresses | Bloom amplification; noise in shadows; color drift under upscale |

**Fetch GT (idempotent):**
```bash
[ -f test-assets/images/demo/gt/nyc-night.jpg ] || \
  curl -L "https://upload.wikimedia.org/wikipedia/commons/2/22/New_York_City_at_night_HDR.jpg" \
    -o test-assets/images/demo/gt/nyc-night.jpg
[ -f test-assets/images/demo/nyc-night-lr756.png ] || \
  convert test-assets/images/demo/gt/nyc-night.jpg \
    -filter Cubic -resize 756x500 test-assets/images/demo/nyc-night-lr756.png
```

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/demo/nyc-night-lr756.png /tmp/out/
```

**Pass criteria (qualitative)**
- Point-light halos do not bleed or double in size
- Dark sky not over-sharpened into structured noise
- Building silhouettes stay crisp without color fringing

---

## Assets needed — fetch on demand

The following categories still have no test asset. Download and create an LR pair locally when you need to test them. The GT files do not need to be committed — just the LR inputs (once created).

### Mixed text + photograph (newspaper scan)

**Why needed:** Halftone photographs next to body text exercises both smooth-region and hard-edge reconstruction simultaneously — the hardest case for a single upscale pass.

**Source:**
```bash
# New York Times front page — San Francisco earthquake, April 19 1906
# Public domain (pre-1928 US publication) — Wikimedia Commons
# File: 19060419_San_Francisco_Earthquake_-_The_New_York_Times.jpg
curl -s "https://commons.wikimedia.org/w/api.php?action=query&titles=File:19060419_San_Francisco_Earthquake_-_The_New_York_Times.jpg&prop=imageinfo&iiprop=url&format=json" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d['query']['pages'].values())[0]['imageinfo'][0]['url'])"
# Then download the returned URL to /tmp/nyt-1906-gt.jpg

# If original is >= 1280px wide, create LR at 4× downscale
# convert /tmp/nyt-1906-gt.jpg -filter Cubic -resize 320x /tmp/nyt-1906-lr320.png

# Run
# ./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 /tmp/nyt-1906-lr320.png /tmp/out/
```

**What to check:** Body text serifs intact; halftone dot pattern suppressed or preserved coherently; headline letters not fragmented; column rule lines straight.

---

### Geometric / technical drawing (blueprint)

**Why needed:** Perfect straight lines, circles, and labeled text — SR tools often introduce curvature or fringe on lines that should be pixel-sharp.

**Source — large option:**
```bash
# Seek a higher-resolution blueprint on Wikimedia Commons:
# https://commons.wikimedia.org/wiki/Category:Blueprints
# https://commons.wikimedia.org/wiki/Category:Technical_drawing
# Filter for originals >= 1500px on the long axis.
# The Everglades Canal blueprint (554×750) is too small for a 4× demo:
#   https://upload.wikimedia.org/wikipedia/commons/0/04/Blueprint_for_Everglades_canals1921.jpg
# Use it only as a content reference, not a resolution benchmark.
```

**What to check:** All straight lines remain straight (no wobble); circle outlines round; text labels legible without fringing; fine grid lines not merged or dropped.

---

## Gap summary

| Category | Asset | Status |
|---|---|---|
| Fine repeating texture | butterfly | Committed ✓ |
| Face / smooth gradient | baby | Committed ✓ |
| Natural organic texture | bsd_45096 (starfish) | Committed ✓ |
| Architecture / hard geometry | budapest-parliament | Committed ✓ |
| Text / signage / hard edges | 76-ball-sign | Committed ✓ |
| Historical scan / noise | nypl-1908-scan | Committed ✓ |
| Foliage / chaotic fine detail | flower-foliage | Committed ✓ |
| Night / low-light | nyc-night | Committed ✓ |
| Historical video / motion | sf-market-street-1906 | Committed ✓ |
| Mid-century color video | prelinger-france-1947 | Committed ✓ |
| Mixed text + halftone photo | — | Fetch on demand (see above) |
| Geometric / technical drawing | — | Fetch on demand (see above) |
