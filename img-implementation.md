# Image Upscaling — Implementation Plan

## Tool: Real-ESRGAN (Python, repo install)

### Why Real-ESRGAN Python over the alternatives

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

## Pre-Mortem Risks (diagnostic/pre-mortem)

| Risk | Signal | Prevention |
|---|---|---|
| BasicSR/facexlib version conflicts | pip install errors, import failures at runtime | Install in isolated venv; pin requirements.txt from the repo |
| VRAM OOM on large images or 4x scale | CUDA OOM crash mid-batch | Always set `--tile 512` as default; tune down to 256 on 4 GB VRAM |
| Model weight download failure (first run) | Hangs or 404 on first inference | Pre-download weights manually to `weights/` before batch run |
| Silent output corruption on batch | Zero-byte or truncated PNGs with exit 0 | Post-run: count output files vs input files; spot-check file sizes |
| Face enhance degrades non-face content | Halos/artifacts on architectural/macro photos | Expose `--face_enhance` as explicit opt-in flag; off by default |
| Path with spaces or special chars breaks inference script args | FileNotFoundError inside Python | Quote all paths in wrapper; test with a path-with-spaces fixture |

---

## Prerequisites

### System check commands

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

### System packages

```bash
sudo apt update && sudo apt install -y python3 python3-pip python3-venv git libgl1 libglib2.0-0
```

`libgl1` and `libglib2.0-0` are required by OpenCV (used inside BasicSR) on headless Ubuntu.

---

## Install Real-ESRGAN

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

## Wrapper Script: upscale-image.sh

### Design

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

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Bad argument / invalid flag |
| 2 | Missing dependency or unreadable INPUT |
| 3 | Inference failure (Python non-zero exit) |

### File locations

```
data-restoration-vid-img-aud/
  scripts/
    upscale-image.sh     ← wrapper (this plan)
    upscale-video.sh     ← video wrapper (vid-implementation.md)
  img-implementation.md  ← this file
  vid-implementation.md
```

---

## Test Plan (debug skill — Phase 1 evidence first)

### Smoke test — run before any batch work

```bash
# Dry run — prints resolved command
./scripts/upscale-image.sh -n ~/test-images/sample.jpg /tmp/out/

# Real run — single image
./scripts/upscale-image.sh ~/test-images/sample.jpg /tmp/out/

# Verify output
file /tmp/out/sample_out.png
identify /tmp/out/sample_out.png   # if imagemagick installed; confirm 4x dimensions
```

### Validation checklist

- [ ] Output file exists and is non-zero bytes
- [ ] Output resolution = 4× input (both dimensions)
- [ ] Output format matches `-f` flag
- [ ] Batch mode: output count == input image count
- [ ] `--tile 256` run completes without CUDA OOM on 4 GB VRAM scenario
- [ ] Custom `-m /path/to/custom.pth` loads and runs without error
- [ ] Face enhance flag produces visibly different output on portrait photo

### Error path tests

```bash
./scripts/upscale-image.sh missing.jpg /tmp/out/         # expect exit 2
./scripts/upscale-image.sh sample.jpg /no-write/out/     # expect exit 2
./scripts/upscale-image.sh -s abc sample.jpg /tmp/out/   # expect exit 1
./scripts/upscale-image.sh -f bmp sample.jpg /tmp/out/   # expect exit 1
./scripts/upscale-image.sh -m /nonexistent.pth s.jpg /tmp/out/ # expect exit 2
```

### Batch integrity check

```bash
INPUT_COUNT=$(find ~/test-images/ -maxdepth 1 -name '*.jpg' -o -name '*.png' | wc -l)
OUT_COUNT=$(find /tmp/out/ -maxdepth 1 -name '*.png' | wc -l)
[ "$INPUT_COUNT" -eq "$OUT_COUNT" ] && echo "PASS: counts match" || echo "FAIL: $INPUT_COUNT in, $OUT_COUNT out"
```

---

## Code Review Gates (code-review skill)

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

## Model Reference

| Model name (`-m`) | Best for | Scale |
|---|---|---|
| `RealESRGAN_x4plus` | General photos, live-action | 4x |
| `RealESRGAN_x4plus_anime_6B` | Anime, illustrations, line art | 4x |
| `RealESRGAN_x2plus` | Light upscale, fine detail preservation | 2x |
| `realesr-animevideov3` | Anime video frames (also useful for stills) | 4x |
| `/path/to/custom.pth` | HAT, DAT, or any BasicSR-compatible community model | varies |

Custom `.pth` files (HAT, DAT variants) from community sources load directly via `-m /abs/path`. No code change needed.

---

## Implementation Sequence

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

## Decision Log (diagnostic/decision-journal)

| Date | Decision | Rationale | Expected outcome | Confidence | Check-in |
|---|---|---|---|---|---|
| 2026-05-20 | Real-ESRGAN Python over ncnn binary | ncnn binary model-locked; Python loads any .pth — matches "most control and flexibility" requirement | Able to swap models without pipeline changes | 90% | After first custom model test |
| 2026-05-20 | Tile default 512 (not 0/auto) | 3050/3060 Ti 4-8 GB VRAM OOM risk on 4x large images; 512 safe default per community reports | No OOM on images up to 4K input | 80% | After VRAM stress test |
| 2026-05-20 | Face enhance off by default | Non-portrait images degrade with GFPGAN pass; safer as opt-in | No artifacts on non-portrait batches | 95% | After batch of mixed content |
