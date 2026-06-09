# data-restoration-vid-img-aud

## Project
Local, open-source CLI upscaling for images and video; runs fully on-device (Ubuntu, RTX 3050–3060 Ti class GPU, 32 GB RAM).

## Quickstart
1. Verify GPU: `nvidia-smi`
2. **Images** — follow [img-implementation.md](img-implementation.md) (Real-ESRGAN Python install + venv)
3. **Video** — follow [vid-implementation.md](vid-implementation.md) (Video2X binary install)
4. Run smoke tests from each plan before any batch work

## Stack
- Image upscaling: Real-ESRGAN Python (BasicSR), GFPGAN (face enhance)
- Video upscaling: Video2X (ncnn backend, wraps Real-ESRGAN / Anime4K)
- Frame handling: FFmpeg
- Runtime: Python 3.8+, CUDA 11.8+, NVIDIA driver ≥ 525
- Shell: bash (POSIX)

## Happy path — image upscaling

Drop any JPEG or PNG anywhere and pass its path. No special folder required.

```bash
# 1. Upscale a single photo
./scripts/upscale-image.sh photo.jpg output/images/
```

While running you will see a progress bar in the terminal:
```
[========--------] 1/2  remaining: 00:00:42
```

On success the script exits 0 and prints nothing extra. The output file is at:
```
output/images/photo_out.png
```

```bash
# 2. Verify the output dimensions are 4× the input
identify -format '%f: %wx%h\n' photo.jpg output/images/photo_out.png
# photo.jpg: 665x527
# photo_out.png: 2660x2108
```

If `identify` is not installed, use Python:
```bash
python3 -c "
from PIL import Image
for p in ['photo.jpg', 'output/images/photo_out.png']:
    i = Image.open(p); print(p, i.width, i.height)
"
```

```bash
# 3. Upscale a folder of images (batch)
./scripts/upscale-image.sh -b test-assets/images/ output/images/
# → output/images/ will contain one PNG per input file
```

## Happy path — video upscaling

```bash
# 1. Upscale a video clip (this takes a long time — ~38 min for a 10 s 320×180 clip on RTX 3050)
./scripts/upscale-video.sh test-assets/videos/prelinger-france-1947-30s.mp4 output/video/prelinger-4x.mp4
```

Progress bar during encode:
```
[============----] 72%  fps=0.10  remaining: 00:42:15
```

```bash
# 2. Verify output dimensions and duration
ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,codec_name \
  -show_entries format=duration \
  -of default=noprint_wrappers=1 output/video/prelinger-4x.mp4
# width=2560
# height=1920
# codec_name=h264
# duration=30.033333
```

The output width should be exactly 4× the input width (640 × 4 = 2560).

## Where to put your own media

The scripts accept any file path — you are not required to use `test-assets/`. However:

| Purpose | Drop files here | Notes |
|---|---|---|
| Quick test (not committed) | `test-assets/images/` or `test-assets/videos/` | gitignored — safe to add anything |
| Permanent input library | Any directory outside the repo | Pass the full path to the script |
| Batch job | Any directory | Pass with `-b` flag |

```bash
# Any of these work
./scripts/upscale-image.sh ~/Pictures/old-photo.jpg ~/Pictures/upscaled/
./scripts/upscale-image.sh -b ~/Photos/album/ output/images/
./scripts/upscale-video.sh /mnt/archive/family/home-movie.mp4 output/video/home-movie-4x.mp4
```

Files placed in `test-assets/images/` or `test-assets/videos/` are gitignored (except the two committed test files). Use that folder for anything you want to run without risking an accidental commit.

## Commands

```bash
# Upscale with non-default options
./scripts/upscale-image.sh -s 2 -m RealESRGAN_x2plus -f jpg photo.jpg out/
./scripts/upscale-video.sh -e anime4k anime-clip.mp4 out/upscaled.mp4

# Dry run — print the exact command that would be run, without executing
./scripts/upscale-image.sh -n photo.jpg out/
./scripts/upscale-video.sh -n clip.mp4 out/up.mp4

# JSON summary on stdout (useful for scripting)
./scripts/upscale-image.sh -j photo.jpg out/
# → {"input":"photo.jpg","output":"out/","model":"RealESRGAN_x4plus","scale":4,"format":"png","files_written":1}

# GPU readiness check (all 4 layers: driver, CUDA, torch, Vulkan)
./scripts/check-gpu.sh

# Fetch real test media (public domain, gitignored)
./scripts/download-test-media.sh

# Run tests
./scripts/test.sh               # fast (~30 s): GPU + arg validation + smoke
./scripts/test.sh --integration # + batch on real photos + video source validation (~2 min)
```

## Architecture
- `scripts/` → POSIX shell wrappers; validate inputs, delegate to upstream tools
- `scripts/upscale-image.sh` → image wrapper (Real-ESRGAN); exits 0/1/2/3
- `scripts/upscale-video.sh` → video wrapper (Video2X); exits 0/1/2
- `scripts/check-gpu.sh` → validates nvidia-smi, CUDA version, torch CUDA device, Vulkan ICD; exits 1 if any check fails
- `scripts/test.sh` → test suite; generates its own 100×100 synthetic image at runtime; `--integration` flag enables batch + video output tests
- `img-implementation.md` → full image setup plan, pre-mortem risks, test plan, model reference
- `vid-implementation.md` → full video setup plan, pre-mortem risks, test plan
- `local-upscaling-audio.md` → audio tool survey (AudioSR, DeepFilterNet); not yet implemented

## Error reference

All errors print to **stderr** and exit with a non-zero code. Stdout is never polluted by error messages.

### upscale-image.sh exit codes

| Exit code | Message | Cause | Fix |
|---|---|---|---|
| 1 | `Flag -X requires an argument` | Flag given without a value | Provide the missing value, e.g. `-s 4` |
| 1 | `Unknown flag: -X` | Unrecognised flag | Run with no args to see usage |
| 1 | `SCALE must be a positive integer, got: X` | `-s abc` or `-s 0` | Use `-s 2`, `-s 4`, etc. |
| 1 | `TILE must be a non-negative integer, got: X` | `--tile abc` | Use `--tile 512` or `--tile 0` |
| 1 | `FORMAT must be png, jpg, or webp, got: X` | `-f bmp` or similar | Only `png`, `jpg`, `webp` are supported |
| 2 | `GPU not accessible — nvidia-smi failed` | NVIDIA driver not loaded or no GPU | Run `nvidia-smi`; ensure driver is loaded |
| 2 | `Python venv not found at tools/realesrgan-venv/...` | Setup not run | Run `scripts/setup.sh` |
| 2 | `inference_realesrgan.py not found at ...` | Real-ESRGAN install incomplete | Re-run `scripts/setup.sh` |
| 2 | `Model file not found: /path/to/model.pth` | Custom model path doesn't exist | Check the path; omit `-m` to use the default |
| 2 | `Batch mode: INPUT must be a directory, got: X` | `-b` used with a file path | Pass a directory with `-b`, not a file |
| 2 | `INPUT not found: X` | File or directory doesn't exist | Check path and spelling |
| 2 | `Cannot create OUTPUT directory: X` | Parent path doesn't exist or no permission | Create the parent dir first |
| 2 | `OUTPUT directory not writable: X` | Permission denied on output dir | Check `ls -ld` on the directory |
| 3 | `Inference failed (exit N)` | Real-ESRGAN crashed mid-run | Check stderr above; usually OOM (lower `--tile`) or corrupt input |
| — | `WARNING: < 10 GB free in X` | Disk space low — not fatal | Free space; large batches can fill disks quickly |

### upscale-video.sh exit codes

| Exit code | Message | Cause | Fix |
|---|---|---|---|
| 1 | `Flag -X requires an argument` | Flag without value | Provide the value |
| 1 | `Unknown flag: -X` | Unrecognised flag | Check usage |
| 1 | `ENGINE must be realesrgan or anime4k, got: X` | `-e ffmpeg` or misspelled | Use `-e realesrgan` or `-e anime4k` |
| 1 | `SCALE must be a positive integer, got: X` | Non-integer scale | Use `-s 4` |
| 2 | `video2x not found — run scripts/setup.sh or set VIDEO2X env var` | Binary missing | Run `scripts/setup.sh`; or set `VIDEO2X=/path/to/binary` |
| 2 | `ffprobe not found on PATH (install ffmpeg)` | ffmpeg not installed | `sudo apt install ffmpeg` |
| 2 | `GPU not accessible — nvidia-smi failed` | No GPU / driver not loaded | Run `nvidia-smi` |
| 2 | `INPUT not found: X` | File doesn't exist | Check path |
| 2 | `INPUT is not a valid video file: X` | Passed an image, text file, or corrupt video | Confirm the file plays in a media player |
| 2 | `OUTPUT directory not writable: X` | Permission denied | Check dir permissions |
| N | `video2x failed (exit N)` | video2x itself exited non-zero | Check stderr above; N is video2x's own exit code |
| — | `WARNING: < 50 GB free in X` | Disk space low — not fatal | Free space; 30 s of 640×480 video generates ~10 GB of temp frames |

### check-gpu.sh

Exits 1 if any check fails; each failing check prints `[FAIL] reason` to stdout. Run it before any upscaling job:

```
[PASS] nvidia-smi: NVIDIA GeForce RTX 3050 Laptop GPU
[PASS] CUDA version: 12.x
[PASS] torch CUDA device: NVIDIA GeForce RTX 3050 Laptop GPU
[PASS] Vulkan NVIDIA ICD present (video2x GPU acceleration available)
```

If torch shows `[FAIL]`, Real-ESRGAN will fall back to CPU — inference will be 10–50× slower.  
If Vulkan shows `[FAIL]`, video2x will fall back to CPU — encode will be unusably slow.

## Rules
- Always run a 30-second / single-image smoke test before any long batch job
- Pre-download model weights before batch runs — never rely on auto-download mid-job
- IMPORTANT: set `--tile 512` (image) by default; never run tilesize=0 on inputs > 2K without confirming VRAM headroom first
- Output dirs must be on SSD; video pipelines create large temp files
- Face enhancement (`-F`) is opt-in only — degrades non-portrait content

## Workflow
- New tool or model: add a section to the relevant `*-implementation.md` first; get approval before coding
- Commits: `#type, what` (add/fix/doc/refactor) — no Co-Authored-By
- Test gate: smoke test + error path tests pass before any batch use
- Ask before changing wrapper exit-code contracts or default flag values

## Design Principles
- Local-first: no cloud upload, no external API calls
- CLI-first: no GUI dependencies; every tool composable via shell
- Fail fast: all boundary validation at script entry; errors to stderr with non-zero exit
- Model-agnostic: wrappers accept any `.pth` file path; no model names hardcoded in logic

## Output resolution depends on input size

The scripts scale by a fixed multiplier (4× default). Output resolution is entirely determined by input:

| Input | 4× output | ≥ 1080p? |
|---|---|---|
| 480×270 | 1920×1080 | ✓ exactly 1080p |
| 854×480 (480p) | 3416×1920 | ✓ exceeds 1080p |
| 1280×720 (720p) | 5120×2880 | ✓ near 4K |
| 320×180 (test clip) | 1280×720 | ✗ only 720p |

**The bundled `realesrgan-plus` model in Video2X 6.4.0 is 4× only** — no 2× or 6× variant is included. To reach 1080p from a very low-res source you would need to run two passes or use a different model.

## Real test media

`test-image.png` and `test-clip.mp4` are synthetic assets (gradients, solid colors). Real-ESRGAN is trained on natural image degradation; it produces little visible improvement on artificial inputs. Use the real media files for meaningful quality evaluation.

**Fetch all four assets automatically:**
```bash
./scripts/download-test-media.sh          # download images + videos
./scripts/download-test-media.sh --check  # verify files exist without downloading
```

**Assets used (all public domain):**

| File | Source | License | Dimensions |
|---|---|---|---|
| `test-assets/images/canal-street-1900s.jpg` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Canal_Street_Bourbon_to_St_Chas_1900s.jpg) — Canal Street New Orleans 1900s | Public domain | 665×527 |
| `test-assets/images/church-building-1906.jpg` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:First_Saint_Rose_of_Lima_Roman_Catholic_Church_building_with_inset_of_Father_Henry_F._Murray_1906.jpg) — First Saint Rose Church 1906 | Public domain | 730×580 |
| `test-assets/videos/prelinger-france-1947-30s.mp4` | [Internet Archive](https://archive.org/details/dph2646mbps640x480) — Prelinger Archives, Dorothy in France 1947 | Public domain | 640×480, 30 s |
| `test-assets/videos/sf-market-street-1906-30s.mp4` | [Internet Archive](https://archive.org/details/san-francisco-market-street-in-1906-wsound-trac) — San Francisco Market Street 1906 | Public domain | 640×480, 30 s |

ToS compliance: Internet Archive `robots.txt` only disallows `/control/` and `/report/`; downloads are fully allowed. Wikimedia upload CDN only disallows `/wikipedia/commons/archive/`; current files are fully allowed.

**Do not commit test media to this repo.** Place files in `test-assets/images/` or `test-assets/videos/` — the gitignore blocks them. Only `test-image.png` and `test-clip.mp4` are tracked.

## Roadmap — hardware upgrades for highest-end output

Current bottleneck: VRAM (4–8 GB on RTX 3050/3060 Ti) forces `--tile 512`, which can leave seam artifacts and blocks the largest model variants entirely.

| Upgrade | Why | Impact |
|---|---|---|
| RTX 4090 (24 GB VRAM) | Eliminates tiling on images up to ~8K output; unlocks HAT-L and DAT-L (largest, highest-quality community models) | Highest — removes the primary quality ceiling |
| RTX 4080 / 4070 Ti (16 GB VRAM) | Removes tiling on most real-world inputs; HAT-S/DAT-S run without tile seams | High |
| 64 GB system RAM | AudioSR and longer video pipelines buffer more frames without paging | Medium — audio/video only |
| NVMe SSD (PCIe 4.0+) | Video frame extraction and reassembly I/O; large batch image reads | Medium — throughput, not quality |

**Priority order:** GPU VRAM → system RAM → storage.  
Any RTX 40-series with ≥ 16 GB VRAM unlocks the full model stack (HAT-L, DAT-L, RealESRGAN x8) and removes tiling as a quality concern for images and video frames. Audio upscaling (AudioSR) gains the least from GPU upgrades specifically; it benefits more from RAM headroom.

---

## Out of scope
- Cloud upscaling services
- GUI tools (Upscayl, Chainner — surveyed in original readme; not implemented here)
- Anime-only workflows (Anime4K, Waifu2x) — available as `-e anime4k` flag but not the primary path
- Audio upscaling implementation (`local-upscaling-audio.md` is reference only; no scripts yet)
