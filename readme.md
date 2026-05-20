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

## Commands
- Upscale image: `./scripts/upscale-image.sh [-s SCALE] [-m MODEL] [-f FORMAT] [-t TILE] [-F] [-b] [-j] [-n] INPUT OUTPUT`
- Upscale video: `./scripts/upscale-video.sh [-s SCALE] [-e ENGINE] [-j] [-n] INPUT OUTPUT`
- Dry run (either): pass `-n` to print command without executing
- GPU check: `nvidia-smi`
- Disk check: `df -h .`

## Architecture
- `scripts/` → POSIX shell wrappers; validate inputs, delegate to upstream tools
- `scripts/upscale-image.sh` → image wrapper (Real-ESRGAN); exits 0/1/2/3
- `scripts/upscale-video.sh` → video wrapper (Video2X); exits 0/1/2
- `img-implementation.md` → full image setup plan, pre-mortem risks, test plan, model reference
- `vid-implementation.md` → full video setup plan, pre-mortem risks, test plan
- `local-upscaling-audio.md` → audio tool survey (AudioSR, DeepFilterNet); not yet implemented

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

## Out of scope
- Cloud upscaling services
- GUI tools (Upscayl, Chainner — surveyed in original readme; not implemented here)
- Anime-only workflows (Anime4K, Waifu2x) — available as `-e anime4k` flag but not the primary path
- Audio upscaling implementation (`local-upscaling-audio.md` is reference only; no scripts yet)
