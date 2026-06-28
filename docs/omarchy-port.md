# Omarchy port — change log + open stack question

Tracks the V3 multi-platform work as it surfaces on the Omarchy (Arch Linux) dev box.
Target platforms for v3: **Mac · Ubuntu 24.04 · WSL2 Ubuntu 24.04 · Omarchy**.

Dev box (2026-06-25): Arch Linux, **Python 3.14** (system, PEP 668), RTX 3050 Laptop,
driver 595.71.05, CUDA 13.2, ffmpeg/imagemagick present. No system pip/PIL/torch.

---

## Changes made (Omarchy adaptation)

| Area | Before (Ubuntu-era) | After (Omarchy) | Status |
|---|---|---|---|
| TUI runtime | `python3 scripts/tui.py` (assumed global Textual) | project `.venv/` + Textual 8.2.7; `tool` auto-prefers `.venv/bin/python3` | ✅ done, tested |
| video2x | AppImage 6.4.0 download+extract | unchanged — AppImage is self-contained, works as-is | ✅ installed, GPU encode verified (RealCUGAN 2×) |
| test-media portrait LR | Python + `PIL.Image` (system Pillow) | ImageMagick `magick … PNG24:` (forces 3-ch RGB, no Pillow dep) | ✅ done, tested |
| Image backend (Real-ESRGAN) | pinned cu118 wheels off **system Python ≤3.12** (absent on Omarchy) | **self-contained**: `setup.sh` provisions a project-local **Python 3.12 via mise** (user-space, no sudo), isolated venv under `tools/`, original cu118 wheels. No system packages. | ✅ done, tested — real GPU inference 100×100→400×400 |
| basicsr install on 3.14 | n/a | avoided — 3.12 predates the PEP 667 `locals()` break that crashes basicsr's `setup.py` | ✅ resolved by 3.12 |
| numpy/scipy conflict | `numpy<2` only | also pin **`scipy<1.13`** — newer scipy is built for numpy 2.x (`np.long`) and crashes on numpy 1.26 | ✅ fixed in setup.sh |
| check-gpu.sh Vulkan ICD | `find /usr/share/vulkan/icd.d /etc/vulkan/icd.d` | scan only existing dirs — missing `/etc/vulkan/icd.d` made `find` non-zero and `pipefail` masked the match (false FAIL on Omarchy) | ✅ fixed |
| Skills/instructions | split `.ai/` + `.ai-instructions/` | consolidated to single `.ai/` (12 skills); CLAUDE.md repointed | ✅ done |

### Why the image backend broke
`setup.sh` pins torch 2.2.0 cu118 wheels that only publish for CPython ≤3.12. Omarchy
ships only CPython 3.14, so the Real-ESRGAN venv can't be built. Even `upscale-image.sh -n`
(dry-run) hard-requires that venv, so the **entire** test suite aborts at the first image
step without it. This is the single blocking dependency for a green suite on Omarchy.

---

## OPEN QUESTION — which software is objectively better for the job?

The Omarchy break exposed that our pain is concentrated in **one dependency choice**: the
PyTorch + `basicsr` image path. This should be an evaluated, documented decision rather than
inertia. Resolve before committing to a v3 stack.

**Objective criteria** (score each candidate):
1. Portability across all 4 targets (Mac / Ubuntu / WSL2 / Omarchy) with one install path.
2. Coupling to the system Python version (lower = better; this is what broke).
3. Maintenance burden / upstream health (`basicsr` is effectively unmaintained).
4. Throughput on the reference job (RTX 3050; see roadmap).
5. Feature coverage — esp. GFPGAN face-enhance, tiling/VRAM control, model breadth.
6. Output quality vs Topaz (ties to roadmap's existing model-quality open question).

### Decision 1 — image inference engine
| Candidate | Portability | Python coupling | Maintenance | Face-enhance | Notes |
|---|---|---|---|---|---|
| **Real-ESRGAN (PyTorch + basicsr)** — current | poor (torch/python pinning) | high | poor (basicsr abandoned) | ✅ GFPGAN | source of the Omarchy break |
| **realesrgan-ncnn-vulkan** (precompiled Vulkan bin) | strong (Win/Mac/Linux bins) | **none** | ok | ❌ no GFPGAN | same models; video2x already uses NCNN/Vulkan |
| **Arch pacman python-pytorch-cuda** | Arch-only | high (system py) | good (Arch-maintained) | ✅ | native to Omarchy, not the other 3 targets |
| **uv/pyenv-managed Python 3.12 + current wheels** | strong (all 4) | decoupled | good | ✅ | keeps torch but unpins from system python |

Tension: NCNN-Vulkan kills the whole Python-version problem and matches the video path, but
drops GFPGAN. If face-enhance is essential, a uv-managed torch env is the portable torch route.

### Decision 2 — dependency sourcing / Python management
pinned pip wheels (broke) vs Arch pacman (Arch-only) vs **uv/pyenv-managed interpreter** (one
path for all 4 targets, decoupled from whatever system Python each platform ships). Leaning
uv as the cross-platform answer; pacman is the fast unblock for *this box only*.

### Decision 3 — video2x distribution
AppImage covers Linux (Omarchy/Ubuntu/WSL2) but **not Mac**. Mac needs brew/source build or a
different NCNN front-end. Cross-platform packaging is unsolved for the Mac target.

---

## Immediate unblock (this box)
`setup.sh` is fully self-contained — **no sudo, no system packages**:
```
./scripts/setup.sh
```
It provisions a project-local Python 3.12 (via mise, falling back to uv, then a real
system python3.12), builds an isolated venv under `tools/`, installs the proven cu118
torch 2.2.0 + torchvision 0.17.0 wheels, then basicsr/facexlib/gfpgan (numpy<2 + scipy<1.13
pinned in lockstep), patches basicsr for the torchvision 0.17 `functional_tensor` removal,
installs video2x (AppImage), and fetches weights + test media. Then `scripts/test.sh` should
go green. This is the "unblock now" path; the **open question above decides the durable v3 stack.**
