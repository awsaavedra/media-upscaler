# Implementation record — image & video pipelines

> Dev spec — implemented and shipped. Kept as the implementation record; not a user guide.

---

## Image Upscaling — Implementation Plan

### Tool: Real-ESRGAN (Python, repo install)

#### Why Real-ESRGAN Python over the alternatives

| Tool | CLI? | Model flexibility | Control | Verdict |
|---|---|---|---|---|
| Upscayl | No (GUI only) | Low | Low | Out — GUI |
| Chainner + HAT/DAT | No (node-graph GUI) | High | High | Out — GUI |
| realesrgan-ncnn-vulkan (binary) | Yes | Medium (bundled models only) | Medium | Out — model-locked |
| **Real-ESRGAN Python (repo)** | **Yes** | **High — any .pth/.onnx file** | **High** | **Selected** |

Real-ESRGAN Python wins because:
- Full CLI via `inference_realesrgan.py`; batch and single-file modes
- Loads any community model file (.pth): swap in HAT, DAT, or RealESRNet variants without changing the pipeline
- Tile mode (`--tile`) manages VRAM independently of scale factor — critical on 3050/3060 class GPUs
- Optional face enhancement pass (GFPGAN integration, `--face_enhance`)
- Output format control (PNG / JPG / WebP)
- Scriptable: repeatable results from identical flags; no GUI state

---

### Pre-Mortem Risks (diagnostic/pre-mortem)

| Risk | Signal | Prevention |
|---|---|---|
| BasicSR/facexlib version conflicts | pip install errors, import failures at runtime | Install in isolated venv; pin requirements.txt from the repo |
| VRAM OOM on large images or 4x scale | CUDA OOM crash mid-batch | Always set `--tile 512` as default; tune down to 256 on 4 GB VRAM |
| Model weight download failure (first run) | Hangs or 404 on first inference | Pre-download weights manually to `weights/` before batch run |
| Silent output corruption on batch | Zero-byte or truncated PNGs with exit 0 | Post-run: count output files vs input files; spot-check file sizes |
| Face enhance degrades non-face content | Halos/artifacts on architectural/macro photos | Expose `--face_enhance` as explicit opt-in flag; off by default |
| Path with spaces or special chars breaks inference script args | FileNotFoundError inside Python | Quote all paths in wrapper; test with a path-with-spaces fixture |

---

### Prerequisites

#### System check commands

```bash
# Verify GPU
nvidia-smi

# Verify Python 3.8+
python3 --version

# Verify pip
python3 -m pip --version

# Verify git
git --version

# Check disk (model weights ~200 MB each; large batches need SSD headroom)
df -h ~
```

#### System packages

```bash
sudo apt update && sudo apt install -y python3 python3-pip python3-venv git libgl1 libglib2.0-0
```

`libgl1` and `libglib2.0-0` are required by OpenCV (used inside BasicSR) on headless Ubuntu.

---

### Install Real-ESRGAN

```bash
# 1. Clone repo
git clone https://github.com/xinntao/Real-ESRGAN.git ~/.local/share/realesrgan
cd ~/.local/share/realesrgan

# 2. Create isolated venv
python3 -m venv venv
source venv/bin/activate

# 3. Install dependencies
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
pip install basicsr facexlib gfpgan
pip install -r requirements.txt
python setup.py develop

# 4. Pre-download default model weights
python -c "
from basicsr.utils.download_util import load_file_from_url
load_file_from_url(
  'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth',
  model_dir='weights'
)
load_file_from_url(
  'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth',
  model_dir='weights'
)
"

# 5. Smoke test (single image)
python inference_realesrgan.py -n RealESRGAN_x4plus -i inputs/lr_image.jpg -o results/ --outscale 4

# 6. Deactivate venv
deactivate
```

> CUDA 11.8 wheel shown above. Replace `cu118` with `cu121` for CUDA 12.1+ (check `nvidia-smi` CUDA version).

---

### Wrapper Script: upscale-image.sh

#### Design

```
upscale-image.sh [OPTIONS] INPUT OUTPUT

Options:
  -s SCALE      Upscale factor integer (default: 4)
  -m MODEL      Model name or /abs/path/to/model.pth (default: RealESRGAN_x4plus)
  -f FORMAT     Output format: png | jpg | webp (default: png)
  -t TILE       Tile size for VRAM management, 0=auto (default: 512)
  -F            Enable face enhancement (GFPGAN; opt-in)
  -b            Batch mode: INPUT is a directory
  -j            Print JSON summary to stdout on completion
  -n            Dry run: print command, do not execute
  -h            Help
```

#### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Bad argument / invalid flag |
| 2 | Missing dependency or unreadable INPUT |
| 3 | Inference failure (Python non-zero exit) |

#### File locations

```
data-restoration-vid-img-aud/
  scripts/
    upscale-image.sh     ← wrapper (this plan)
    upscale-video.sh     ← video wrapper (video section below)
  implementation.md      ← this file (image + video, merged 2026-07-07)
```

---

### Test Plan (debug skill — Phase 1 evidence first)

#### Smoke test — run before any batch work

```bash
# Dry run — prints resolved command
./scripts/upscale-image.sh -n ~/test-images/sample.jpg /tmp/out/

# Real run — single image
./scripts/upscale-image.sh ~/test-images/sample.jpg /tmp/out/

# Verify output
file /tmp/out/sample_out.png
identify /tmp/out/sample_out.png   # if imagemagick installed; confirm 4x dimensions
```

#### Validation checklist

- [ ] Output file exists and is non-zero bytes
- [ ] Output resolution = 4× input (both dimensions)
- [ ] Output format matches `-f` flag
- [ ] Batch mode: output count == input image count
- [ ] `--tile 256` run completes without CUDA OOM on 4 GB VRAM scenario
- [ ] Custom `-m /path/to/custom.pth` loads and runs without error
- [ ] Face enhance flag produces visibly different output on portrait photo

#### Error path tests

```bash
./scripts/upscale-image.sh missing.jpg /tmp/out/         # expect exit 2
./scripts/upscale-image.sh sample.jpg /no-write/out/     # expect exit 2
./scripts/upscale-image.sh -s abc sample.jpg /tmp/out/   # expect exit 1
./scripts/upscale-image.sh -f bmp sample.jpg /tmp/out/   # expect exit 1
./scripts/upscale-image.sh -m /nonexistent.pth s.jpg /tmp/out/ # expect exit 2
```

#### Batch integrity check

```bash
INPUT_COUNT=$(find ~/test-images/ -maxdepth 1 -name '*.jpg' -o -name '*.png' | wc -l)
OUT_COUNT=$(find /tmp/out/ -maxdepth 1 -name '*.png' | wc -l)
[ "$INPUT_COUNT" -eq "$OUT_COUNT" ] && echo "PASS: counts match" || echo "FAIL: $INPUT_COUNT in, $OUT_COUNT out"
```

---

### Code Review Gates (code-review skill)

Before the wrapper script is used in any pipeline:

- [x] No infrastructure imports at logic layer — wrapper only invokes Python subprocess; no model logic in shell
- [x] All external dependencies validated at boundary: python3, inference script path, nvidia-smi, INPUT readable
- [x] No magic numbers — TILE=512, SCALE=4, FORMAT=png all named variables with comments on defaults
- [x] SRP: script validates inputs and delegates to Python inference; no inline upscaling logic
- [x] POSIX-compliant flags: single-char only, no `--long-only` without short form
- [x] Exit codes: 0/1/2/3 as contracted above; no silent failures (confirmed by error path tests)
- [x] No interactive prompts; all errors to stderr
- [x] Batch and single-file mode share the same validation path — no duplicated checks

---

### Model Reference

| Model name (`-m`) | Best for | Scale |
|---|---|---|
| `RealESRGAN_x4plus` | General photos, live-action | 4x |
| `RealESRGAN_x4plus_anime_6B` | Anime, illustrations, line art | 4x |
| `RealESRGAN_x2plus` | Light upscale, fine detail preservation | 2x |
| `realesr-animevideov3` | Anime video frames (also useful for stills) | 4x |
| `/path/to/custom.pth` | HAT, DAT, or any BasicSR-compatible community model | varies |

Custom `.pth` files (HAT, DAT variants) from community sources load directly via `-m /abs/path`. No code change needed.

---

### Implementation Sequence

1. [x] Prerequisite checks: `nvidia-smi` (driver 580.159.03), `python3` (3.12.3 via /usr/bin), `git` (2.43.0)
2. [x] `libgl1` already installed; `libglib2.0-0` present as shared lib; no additional apt needed
3. [x] Cloned Real-ESRGAN to `tools/realesrgan/` (local to repo, not `~/.local/share`)
4. [x] Venv created with python3.12; torch 2.2.0+cu118, basicsr, facexlib, gfpgan installed; numpy pinned to <2 after all deps to avoid torch 2.2 / numpy 2.x incompatibility
5. [x] `RealESRGAN_x4plus.pth` and `RealESRGAN_x4plus_anime_6B.pth` downloaded to `tools/realesrgan/weights/`
6. [x] Inference smoke test: 320×240 → 1280×960 (4×); output 811 KB PNG confirmed
7. [x] `scripts/upscale-image.sh` exists; updated to resolve `REALESRGAN_DIR` from `tools/realesrgan/`
8. [x] Script is executable; `-n` dry run prints correct absolute paths
9. [x] Real run smoke test passed: 320×240 input → 1280×960 output (4× confirmed via ffprobe)
10. [x] Run error path tests — all 5 paths pass (missing INPUT exit 2, invalid SCALE exit 1, invalid FORMAT exit 1, nonexistent model path exit 2, unwritable OUTPUT exit 2)
11. [x] Batch integrity check — 5-image folder: 5 in / 5 out, output 1280×960 confirmed (4× from 320×240)
12. [x] Code review gates — all gates pass (see checklist below)

> **Note:** Install is now fully local via `scripts/setup.sh`; no global `~/.local` writes.
> Python 3.12 requires torch cu118 wheel; mise injects Python 3.14 so setup.sh explicitly uses `/usr/bin/python3.12`.
> `basicsr` `functional_tensor` patch applied by setup.sh; numpy downgraded to <2 last to fix torch 2.2 C-extension incompatibility.

---

### Decision Log (diagnostic/decision-journal)

| Date | Decision | Rationale | Expected outcome | Confidence | Check-in |
|---|---|---|---|---|---|
| 2026-05-20 | Real-ESRGAN Python over ncnn binary | ncnn binary model-locked; Python loads any .pth — matches "most control and flexibility" requirement | Able to swap models without pipeline changes | 90% | After first custom model test |
| 2026-05-20 | Tile default 512 (not 0/auto) | 3050/3060 Ti 4-8 GB VRAM OOM risk on 4x large images; 512 safe default per community reports | No OOM on images up to 4K input | 80% | After VRAM stress test |
| 2026-05-20 | Face enhance off by default | Non-portrait images degrade with GFPGAN pass; safer as opt-in | No artifacts on non-portrait batches | 95% | After batch of mixed content |

---

## Video Upscaling — Implementation Plan

### Tool: Video2X

#### Why Video2X
- README primary video recommendation; end-to-end local workflow
- Wraps Real-ESRGAN (best general model) + Anime4K backends via ncnn
- Pure CLI, no GUI dependency, pipeline-friendly
- Handles frame extraction, upscale, reassembly, audio mux internally — no manual FFmpeg stitching
- Hardware fit: RTX 3050/3060 Ti + 32GB RAM on 11th-gen Intel H-series is within supported target range

Alternatives considered and rejected:
- Real-ESRGAN + FFmpeg manual pipeline: more steps, more failure surface, better for scripting internals we own
- Anime4K: only for anime/stylized content; not general purpose

---

### Pre-Mortem Risks (diagnostic/pre-mortem)

| Risk | Signal | Prevention |
|---|---|---|
| CUDA driver version mismatch with ncnn backend | `video2x` segfaults or reports no GPU | Run `nvidia-smi` before install; pin driver ≥ 525 |
| Temp storage exhaustion on long encodes | Disk full mid-job, corrupt output | Check `df -h`; require ≥ 50 GB free on SSD; set `--output` to SSD path |
| Audio desync after reassembly | Audio drifts on variable-frame-rate input | Always pass `--vfr` flag on VFR sources; verify with `ffprobe` first |
| Video2X release instability | Binary segfaults on specific codec | Pin to tested release tag; test on 30-second clip before full encode |
| Frame rate loss | Output fps differs from source | Extract and explicitly pass fps via `--fps`; validate with `ffprobe` post-encode |
| Long encode with no progress feedback | Appears hung | Use `--log-level debug` on first run; monitor GPU with `nvidia-smi dmon` |

---

### Prerequisites

#### System check commands

```bash
# Verify NVIDIA driver
nvidia-smi

# Verify CUDA availability
nvcc --version || nvidia-smi | grep "CUDA Version"

# Verify FFmpeg (used internally by Video2X)
ffmpeg -version | head -1

# Check available disk
df -h /tmp && df -h ~
```

#### Install FFmpeg if missing

```bash
sudo apt update && sudo apt install -y ffmpeg
```

#### NVIDIA driver (if not present)

```bash
# Ubuntu 22.04+
sudo apt install -y nvidia-driver-535 nvidia-utils-535
sudo reboot
```

---

### Install Video2X

Video2X 6.x ships as an **AppImage** for Linux (no tarball). The AppImage requires `libfuse.so.2`; on systems where it is unavailable (WSL2, minimal Ubuntu installs), extract it instead.

#### Option A — native Ubuntu with FUSE (recommended)

Install `libfuse2` once if needed, then run the AppImage directly:

```bash
# Install FUSE if missing (Ubuntu 22.04+)
sudo apt-get install -y libfuse2

# Create dirs
mkdir -p ~/.local/bin ~/.local/share/video2x

# Download latest AppImage (check https://github.com/k4yt3x/video2x/releases for current filename)
curl -L -o ~/.local/share/video2x/Video2X-x86_64.AppImage \
  https://github.com/k4yt3x/video2x/releases/download/6.4.0/Video2X-x86_64.AppImage

chmod +x ~/.local/share/video2x/Video2X-x86_64.AppImage

# Symlink onto PATH
ln -sf ~/.local/share/video2x/Video2X-x86_64.AppImage ~/.local/bin/video2x

# Verify
video2x --version
```

#### Option B — WSL2 or no FUSE (extract AppImage)

```bash
mkdir -p ~/.local/bin ~/.local/share/video2x
curl -L -o ~/.local/share/video2x/Video2X-x86_64.AppImage \
  https://github.com/k4yt3x/video2x/releases/download/6.4.0/Video2X-x86_64.AppImage
chmod +x ~/.local/share/video2x/Video2X-x86_64.AppImage

# Extract (creates squashfs-root/ — no FUSE needed)
cd ~/.local/share/video2x
./Video2X-x86_64.AppImage --appimage-extract

# Symlink the extracted binary
ln -sf ~/.local/share/video2x/squashfs-root/usr/bin/video2x ~/.local/bin/video2x

video2x --version
```

> Release page: https://github.com/k4yt3x/video2x/releases

#### Vulkan GPU prerequisite (native Ubuntu only)

Video2X 6.x uses **Vulkan**, not CUDA directly. On native Ubuntu with an NVIDIA GPU, install the GL/Vulkan ICD matching your driver version:

```bash
# Check your driver version
nvidia-smi | grep "Driver Version"

# Install matching ICD (replace 590 with your major version)
sudo apt-get install -y libnvidia-gl-590

# Confirm GPU is visible to video2x
video2x --list-devices
# Should show your RTX GPU, not just llvmpipe (CPU)
```

> **WSL2 note:** NVIDIA Vulkan is not exposed to Linux in WSL2 by default. Run video2x on native Ubuntu for GPU acceleration.

---

### Wrapper Script: upscale-video.sh

Implements CLI/DevEx rules: POSIX flags, stdin/stdout clean, composable, exit codes as contracts.

#### Design

```
upscale-video.sh [OPTIONS] INPUT OUTPUT

Options:
  -s SCALE     Integer upscale factor (default: 2)
  -e ENGINE    realesrgan | anime4k (default: realesrgan)
  -j           Output JSON summary on completion
  -n           Dry run: print command, do not execute
  -h           Help
```

#### Validation gates (fail-fast)

1. INPUT exists and is a video file (ffprobe check)
2. OUTPUT directory is writable
3. `video2x` binary is on PATH
4. `nvidia-smi` returns exit 0 (GPU accessible)
5. ≥ 10 GB free on OUTPUT's filesystem (warn if < 50 GB)

#### Script skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail

SCALE=2
ENGINE=realesrgan
DRY_RUN=0
JSON_OUT=0

usage() {
  printf 'Usage: %s [-s SCALE] [-e ENGINE] [-j] [-n] INPUT OUTPUT\n' "$0"
  printf '  -s  upscale factor (default: 2)\n'
  printf '  -e  engine: realesrgan | anime4k (default: realesrgan)\n'
  printf '  -j  json summary output\n'
  printf '  -n  dry run\n'
  exit 0
}

while getopts ':s:e:jnh' opt; do
  case $opt in
    s) SCALE=$OPTARG ;;
    e) ENGINE=$OPTARG ;;
    j) JSON_OUT=1 ;;
    n) DRY_RUN=1 ;;
    h) usage ;;
    *) printf 'Unknown flag: -%s\n' "$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

INPUT=${1:?INPUT required}
OUTPUT=${2:?OUTPUT required}

# Boundary validation
command -v video2x >/dev/null 2>&1 || { printf 'video2x not found on PATH\n' >&2; exit 2; }
command -v ffprobe >/dev/null 2>&1 || { printf 'ffprobe not found on PATH\n' >&2; exit 2; }
nvidia-smi >/dev/null 2>&1        || { printf 'GPU not accessible (nvidia-smi failed)\n' >&2; exit 2; }
[ -f "$INPUT" ]                   || { printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2; }
ffprobe -v error "$INPUT" >/dev/null 2>&1 || { printf 'INPUT is not a valid video: %s\n' "$INPUT" >&2; exit 2; }

OUTDIR=$(dirname "$OUTPUT")
[ -w "$OUTDIR" ] || { printf 'OUTPUT directory not writable: %s\n' "$OUTDIR" >&2; exit 2; }

FREE_KB=$(df -k "$OUTDIR" | awk 'NR==2{print $4}')
[ "$FREE_KB" -ge 10485760 ] || printf 'WARNING: < 10 GB free in %s\n' "$OUTDIR" >&2

CMD="video2x -i \"$INPUT\" -o \"$OUTPUT\" -p $ENGINE -s $SCALE"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$CMD"
  exit 0
fi

eval "$CMD"

if [ "$JSON_OUT" -eq 1 ]; then
  printf '{"input":"%s","output":"%s","engine":"%s","scale":%s}\n' \
    "$INPUT" "$OUTPUT" "$ENGINE" "$SCALE"
fi
```

#### File location

```
data-restoration-vid-img-aud/
  scripts/
    upscale-video.sh     ← wrapper
  implementation.md      ← this file (image + video, merged 2026-07-07)
```

---

### Test Plan (debug skill — Phase 1 before any fix)

#### Smoke test (run first, always)

```bash
# 30-second clip, 2x, realesrgan
./scripts/upscale-video.sh -n test-clip.mp4 /tmp/out.mp4      # dry run — prints command
./scripts/upscale-video.sh test-clip.mp4 /tmp/out.mp4          # real run
ffprobe /tmp/out.mp4                                            # verify output is valid video
```

#### Validation checklist

- [ ] `ffprobe` reports output resolution = 2× input resolution
- [ ] Audio present and duration matches source (within 0.1s)
- [ ] No GPU OOM errors in video2x log
- [ ] Output file size > 0 bytes
- [ ] `upscale-video.sh` exits 0 on success, non-zero on each error path

#### Error path tests

```bash
upscale-video.sh missing.mp4 /tmp/out.mp4     # expect exit 2
upscale-video.sh test.mp4 /no-write/out.mp4   # expect exit 2
upscale-video.sh -s abc test.mp4 /tmp/out.mp4 # expect exit 1 or video2x error
```

---

### Code Review Gates (code-review skill)

Before merging the wrapper script:

- [x] No infrastructure imports at logic layer — script has no hardcoded paths; uses `$PROJECT_ROOT/tools/video2x/` resolved at runtime; VIDEO2X env var override supported
- [x] All external dependencies validated at boundary (video2x, ffprobe, nvidia-smi checks; numeric duration check distinguishes video from image/audio)
- [x] No magic numbers — SCALE=4, ENGINE=realesrgan all named variables
- [x] SRP: script validates inputs and delegates entirely to video2x; no inline frame processing
- [x] POSIX-compliant flags (`-s`, `-e`, `-j`, `-n`, `-h`)
- [x] Exit codes: 0 = success, 1 = bad args, 2 = missing dependency/file (confirmed by error path tests)
- [x] No interactive prompts; all errors to stderr, JSON summary to stdout on `-j`
- [x] Output resolution = 4× input — ffprobe confirmed 1280×720 (4× from 320×180)

---

### Implementation Sequence

1. [x] Run prerequisite checks — `nvidia-smi` (driver 580.159.03, CUDA 13.0), `ffmpeg -version` (6.1.1), `df -h` (39 GB free)
2. [x] Download Video2X 6.4.0 AppImage and install via extraction (no libfuse2 on this system)
3. [x] `video2x --version` → confirmed 6.4.0; RTX 3050 detected via Vulkan (libnvidia-gl-580 already installed)
4. [x] `scripts/upscale-video.sh` exists with full validation gates; updated to use `tools/video2x/` local path
5. [x] Script updated for video2x **6.x API** (see note below)
6. [x] `libnvidia-gl-580` already installed; `nvidia_icd.json` present; RTX 3050 shows as Vulkan device 1
7. [x] Synthetic test clip created: `test-assets/videos/test-clip.mp4` (10s, 320×180, 204 KB, CC-free)
8. [x] Smoke test dry-run passes; real run in progress — GPU processing confirmed via Vulkan
9. [x] Validate output with `ffprobe` — 1280×720 ✓ (4× from 320×180), aac audio ✓, 9.92 s duration ✓; confirmed Vulkan device: NVIDIA GeForce RTX 3050 Laptop GPU (0x25e2)
10. [x] Run error path tests — all 5 paths pass (missing INPUT exit 2, image-as-INPUT exit 2 [bug fixed: was exit 0], unwritable OUTPUT exit 2, invalid ENGINE exit 1, invalid SCALE exit 1)
11. [x] Sign off on code review gates — all gates pass; video inference test in scripts/test.sh --integration

> **Note:** `realesrgan-plus` model only ships as x4 in the AppImage; default scale changed to 4.
> `scripts/setup.sh` automates the full local install into `tools/` within the repository.

#### video2x 6.x API changes from original plan

The 6.x release changed its CLI; `upscale-video.sh` has been updated to match:

| Plan assumption | 6.x reality | Fix applied in script |
|---|---|---|
| `-p realesrgan` uses best general model | Default model is `realesr-animevideov3` (anime-optimised) | Now passes `--realesrgan-model realesrgan-plus` |
| `-p anime4k` is a valid processor | `anime4k` is a libplacebo shader, not a processor | Engine `anime4k` now maps to `-p libplacebo --libplacebo-shader anime4k-v4-a` |
| Install via `video2x-linux-amd64.tar.gz` | No tarball; ships as AppImage | Updated install steps above |
| ncnn/CUDA backend | Vulkan backend (Vulkan ICD required for GPU) | Documented Vulkan prerequisite above |

---

### Decision Log (diagnostic/decision-journal)

| Date | Decision | Rationale | Expected outcome | Confidence | Check-in |
|---|---|---|---|---|---|
| 2026-05-20 | Video2X over manual Real-ESRGAN+FFmpeg | End-to-end, fewer failure points, README primary recommendation | Working CLI pipeline with <30 min setup | 80% | After first real encode |
| 2026-05-20 | Real-ESRGAN engine default (not Anime4K) | General video, not anime | Best quality on live-action footage | 85% | After test clip comparison |
| 2026-05-20 | AppImage extraction over direct run | libfuse.so.2 unavailable in WSL2; `--appimage-extract` avoids FUSE entirely | Models found correctly via binary's real path | confirmed | — |
| 2026-05-20 | Use `realesrgan-plus` model explicitly | 6.x changed default to anime model `realesr-animevideov3`; must override for live-action | Correct general-purpose output | confirmed | After first real encode |
| 2026-06-03 | Install tools/ locally within repo | User requirement: no global installs; all tools in `tools/`; gitignored | Reproducible via `scripts/setup.sh` | confirmed | — |
| 2026-06-03 | Wrapper shell script over symlink for video2x | AppImage extraction places binary at `squashfs-root/usr/bin/` but models at `squashfs-root/usr/share/video2x/models/`; video2x resolves `models/` relative to CWD; wrapper CDs to resource dir and absolutizes `-i`/`-o` paths first | Model files found correctly | confirmed | — |
| 2026-06-03 | Default scale changed to 4 | `realesrgan-plus` model only ships as x4 in Video2X 6.4.0 AppImage; x2 variant not bundled; x4 is also the recommended quality setting for live-action | Single working default, no scale mismatch errors | confirmed | — |
| 2026-06-03 | PyTorch 2.2.0 + torch cu118 + numpy<2 (downgraded after deps) | Python 3.12 cu118 oldest available is 2.2.0; numpy 2.x breaks torch 2.2 C extension; downgrading numpy after all deps resolves conflict (tifffile/opencv conflict warnings are non-fatal at inference level) | Real-ESRGAN inference runs | confirmed | After image smoke test |
| 2026-06-03 | basicsr `functional_tensor` patch | torchvision 0.17 removed `torchvision.transforms.functional_tensor`; basicsr 1.4.2 imports it; one-line patch in `degradations.py` fixes import | basicsr imports cleanly | confirmed | — |
| 2026-06-09 | Duration-based video detection in upscale-video.sh | `ffprobe -v error -i <png>` exits 0 (PNG is a valid ffprobe input); must check `format=duration` which returns "N/A" for images — switch to numeric duration check catches images, audio-only, and corrupt files | image-as-INPUT correctly exits 2 | confirmed | error path test run |
