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

### flower-foliage-q20 — JPEG compression artifact removal

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/flower-foliage-lr540-q20.jpg` — 540×360, JPEG Q20 |
| GT | `test-assets/images/demo/gt/flower-foliage.jpg` — 2160×1440 |
| Scale | 4× |
| License | CC0 / public domain — Wikimedia Commons |
| Category | JPEG blocking, DCT ringing, compression noise on top of bicubic blur |
| What it stresses | Model must remove 8×8 DCT block artifacts simultaneously with upscale without over-smoothing |

**Create LR (idempotent):**
```bash
[ -f test-assets/images/demo/flower-foliage-lr540-q20.jpg ] || \
  convert test-assets/images/demo/gt/flower-foliage.jpg \
    -filter Cubic -resize 540x360 -quality 20 \
    test-assets/images/demo/flower-foliage-lr540-q20.jpg
```

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus \
  test-assets/images/demo/flower-foliage-lr540-q20.jpg /tmp/out/
```

**Pass criteria (qualitative)**
- JPEG block boundaries (8×8 grid) not visible in output at full zoom
- Petal and stamen detail still resolved — not over-smoothed to suppress artifacts
- Compare side-by-side against clean `flower-foliage-lr540_out.png`: degraded input should differ (softer restoration, fewer false-high-freq edges)

---

### great-wave — anime / illustration style

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/great-wave-lr600.png` — 600×411 |
| GT | `test-assets/images/demo/gt/great-wave.jpg` — 8242×5640 |
| Effective scale | ~13.7× (run at 4×; compare sub-region qualitatively against GT) |
| License | Public domain — Wikimedia Commons (Hokusai, pre-1828) |
| Category | Ukiyo-e woodblock print — flat colour fills, strong outlines, chaotic wave texture |
| What it stresses | Anime model selection: `x4plus_anime_6B` must preserve illustrative style; `x4plus` photo model injects false grain into flat fills |

**Fetch GT (idempotent):**
```bash
[ -f test-assets/images/demo/gt/great-wave.jpg ] || \
  curl -L "https://upload.wikimedia.org/wikipedia/commons/0/0d/Great_Wave_off_Kanagawa2.jpg" \
    -o test-assets/images/demo/gt/great-wave.jpg
[ -f test-assets/images/demo/great-wave-lr600.png ] || \
  convert test-assets/images/demo/gt/great-wave.jpg \
    -filter Cubic -resize 600x test-assets/images/demo/great-wave-lr600.png
```

**Invocation — anime model (correct)**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus_anime_6B \
  test-assets/images/demo/great-wave-lr600.png /tmp/out-anime/
```

**Invocation — photo model (comparison baseline)**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus \
  test-assets/images/demo/great-wave-lr600.png /tmp/out-photo/
```

**Pass criteria (qualitative)**
- `anime_6B` output: flat blue sky and water fills stay smooth; wave foam lines crisp without photorealistic grain
- `x4plus` output (comparison): typically adds false grain to flat fills — confirms anime_6B is the correct model for this content
- Wave foam curlicues sharp; Mt Fuji silhouette clean line without fringing

---

### douglas-portrait — face enhancement / historical portrait

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/douglas-portrait-lr198.png` — 198×235 |
| GT | `test-assets/images/demo/gt/douglas-portrait.jpg` — 791×938 |
| Scale | 4× (output 792×940 ≈ original GT size) |
| License | Public domain — Wikimedia Commons (Frederick Douglass c1860s daguerreotype) |
| Category | Historical portrait photograph, facial landmarks, halftone degradation |
| What it stresses | GFPGAN face detection at small input (198px); hallucination of features that contradict original expression |

**Fetch GT (idempotent):**
```bash
[ -f test-assets/images/demo/gt/douglas-portrait.jpg ] || \
  curl -L "https://upload.wikimedia.org/wikipedia/commons/8/85/Frederick_Douglass_c1860s.jpg" \
    -o test-assets/images/demo/gt/douglas-portrait.jpg
[ -f test-assets/images/demo/douglas-portrait-lr198.png ] || \
  convert test-assets/images/demo/gt/douglas-portrait.jpg \
    -filter Cubic -resize 198x test-assets/images/demo/douglas-portrait-lr198.png
```

**Invocation — base**
```bash
./scripts/upscale-image.sh -s 4 \
  test-assets/images/demo/douglas-portrait-lr198.png /tmp/out-base/
```

**Invocation — with face enhancement**
```bash
./scripts/upscale-image.sh -s 4 -F \
  test-assets/images/demo/douglas-portrait-lr198.png /tmp/out-face/
```

**Pass criteria (qualitative)**
- Base output: clothing and background sharpened without false textures
- Face-enhanced (`-F`): eyes, nose, and lips visibly improved vs base; detail matches GT portrait expression
- `-F` output must differ from base (confirms GFPGAN fired despite small 198px input)
- No hallucinated facial features that contradict the original expression

---

---

## Image 4K demo set

These three images are used to validate highest-end upscaling to 4K-class output. All LRs are 960px wide (bicubic downscale); 4× produces ≥3840px wide output. GTs are committed as download targets; LRs are committed.

### metro-landscape — dense urban cityscape

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/metro-landscape-lr960.png` — 960×640 |
| GT | `test-assets/images/demo/gt/metro-landscape.jpg` — 5472×3648 |
| Output | 3840×2560 (4K+) |
| License | CC0 — Unsplash via Wikimedia Commons |
| Category | Dense urban buildings, fine window grid, varied facade textures |
| What it stresses | Fine repeated structural elements (windows) at 4K scale; color fidelity on glass/concrete |

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/demo/metro-landscape-lr960.png /tmp/out/
```

**Pass criteria**
- Output dims: 3840×2560
- Window grids sharp without ghosting or doubling
- Sky/building boundary clean; no color fringing on glass facades

---

### portrait-conversation — natural-light multi-face portrait

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/portrait-conversation-lr960.png` — 960×640 |
| GT | `test-assets/images/demo/gt/portrait-conversation.jpg` — 5760×3840 |
| Output | 3840×2560 (4K+) |
| License | CC0 — Unsplash via Wikimedia Commons |
| Category | Two faces, natural window light, clothing texture, background bokeh |
| What it stresses | Multi-face skin rendering at 4K; clothing fabric texture; shallow-DOF background handling |

**Invocation (base)**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/demo/portrait-conversation-lr960.png /tmp/out/
```

**Invocation (face enhance)**
```bash
./scripts/upscale-image.sh -s 4 -F -t 512 \
  test-assets/images/demo/portrait-conversation-lr960.png /tmp/out-face/
```

**Pass criteria**
- Output dims: 3840×2560
- Faces natural — no over-sharpened pores or waxy skin
- Clothing weave distinct; background bokeh smooth without tiling artifacts

---

### yosemite-valley — mountain landscape, natural detail

| Field | Value |
|---|---|
| LR | `test-assets/images/demo/yosemite-valley-lr960.png` — 960×434 |
| GT | `test-assets/images/demo/gt/yosemite-valley.jpg` — 4169×1884 |
| Output | 3840×1736 (4K+ width) |
| License | CC BY-SA 3.0 — Wikimedia Commons |
| Category | Valley panorama — granite cliff faces, pine forest canopy, waterfall, sky gradient |
| What it stresses | Multi-scale natural texture (rock vs trees vs water); distant fine detail; large smooth sky |

**Invocation**
```bash
./scripts/upscale-image.sh -s 4 -m RealESRGAN_x4plus -t 512 \
  test-assets/images/demo/yosemite-valley-lr960.png /tmp/out/
```

**Pass criteria**
- Output dims: 3840×1736
- Granite cliff texture sharp without false grain injection
- Tree canopy distinct, not smeared into uniform green mass
- Sky clean and smooth; no tiling seams at tile boundaries

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
| JPEG compression artifact removal | flower-foliage-q20 | Committed ✓ |
| Anime / illustration style | great-wave (Hokusai) | Committed ✓ |
| Portrait / face enhancement | douglas-portrait (Douglass c1860s) | Committed ✓ |
| 4K cityscape | metro-landscape | Committed ✓ |
| 4K multi-face portrait | portrait-conversation | Committed ✓ |
| 4K mountain landscape | yosemite-valley | Committed ✓ |
| Historical video / motion | sf-market-street-1906 | Committed ✓ |
| Mid-century color video | prelinger-france-1947 | Committed ✓ |
| Mixed text + halftone photo | — | Fetch on demand (see above) |
| Geometric / technical drawing | — | Fetch on demand (see above) |

---

## Test asset sources — vetted safe origins

Merged from `docs/test-assets-vid-img-aud.md` (2026-07-07). Only sources hosted by recognizable publishers over **HTTPS** with documented reuse terms or public-domain status (Blender, NASA, Unsplash, Pexels, LibriVox).

### Images

**Unsplash** — license allows free download, copy, modification, distribution, and use, including commercial.

- Happy family photos: https://unsplash.com/s/photos/happy-family
- Family park photos: https://unsplash.com/s/photos/family-park
- Family in park photos: https://unsplash.com/s/photos/family-in-park
- Park photos: https://unsplash.com/s/photos/park
- Urban park photos: https://unsplash.com/s/photos/urban-park

**NASA** — content generally not subject to copyright in the US; some third-party material on NASA sites is separately marked as copyrighted, so use only clearly NASA-created items.

- NASA Image and Video Library: https://images.nasa.gov
- NASA images hub: https://www.nasa.gov/images/
- NASA Earth image article: https://www.nasa.gov/image-article/hello-world/

### Video

**Big Buck Bunny** — official Blender open movie, Creative Commons Attribution; Blender hosts downloads over HTTPS.

- Project page: https://peach.blender.org
- Download page: https://peach.blender.org/download/
- Official watch page: https://video.blender.org/w/dmhvQNzwBnrWy1iYzVv5g7

**Tears of Steel** — official Blender open movie, Creative Commons Attribution.

- Download page: https://mango.blender.org/download/
- Official watch page: https://video.blender.org/w/hs1zJY8mdr3iH2JNmxpeGV

**Pexels** — photos and videos free for personal and commercial use under the Pexels license.

- Pexels videos homepage: https://www.pexels.com/videos/

### Audio

**LibriVox** — all recordings are public domain in the United States and may be used freely.

- LibriVox homepage: https://librivox.org/
- LibriVox short story collections: https://librivox.org/group/465
- Five Beloved Stories by O. Henry: https://librivox.org/five-beloved-stories-by-o-henry-by-o-henry/

### Removed for security or provenance caution

- Direct archive or mirror links that are not needed when an official HTTPS publisher page exists.
- Generic Internet Archive music items unless clearly necessary and clearly licensed.
- AudioCheck and similar sites — keep only the cleanest combination of licensing clarity and trusted-host simplicity.

### Recommended starter set

- One family portrait from Unsplash.
- One park or foliage image from Unsplash.
- One clearly NASA-created image from the NASA Image and Video Library.
- Big Buck Bunny for animation video.
- Tears of Steel for live-action/VFX video.
- One LibriVox short story chapter for speech audio.
- One short Pexels family-friendly clip if a non-Blender real-world video sample is needed.

### Download safety notes

Even when a source is reputable and uses HTTPS, download only from the official page, avoid browser extensions or third-party downloaders, and scan files locally after download if desired. HTTPS and publisher reputation reduce risk; they do not make every downstream local action risk-free.
