# data-restoration-vid-img-aud

## Project
Local CLI upscaling pipeline for images and video; runs fully on-device (Ubuntu, RTX 3050–3060 Ti, 32 GB RAM).

## Quickstart
1. Verify GPU: `nvidia-smi` — driver must be loaded
2. Run setup: `./scripts/setup.sh` — installs Real-ESRGAN venv and Video2X binary under `tools/`
3. Check GPU readiness: `./scripts/check-gpu.sh`
4. Drop media into `input/images/` or `input/video/`
5. Run: `./scripts/upscale-image.sh input/images/photo.jpg output/images/` or `./scripts/upscale-video.sh input/video/clip.mp4 output/video/clip-4x.mp4`

## Stack
- Image upscaling: Real-ESRGAN Python (BasicSR), `RealESRGAN_x4plus` model
- Video upscaling: Video2X 6.4.0 AppImage (Vulkan backend), `realesrgan-plus` model
- Frame handling: FFmpeg
- Runtime: Python 3.12, CUDA 11.8+, NVIDIA driver ≥ 525

## Commands
- Upscale image: `./scripts/upscale-image.sh input/images/photo.jpg output/images/`
- Upscale image batch: `./scripts/upscale-image.sh -b input/images/ output/images/`
- Upscale video: `./scripts/upscale-video.sh input/video/clip.mp4 output/video/clip-4x.mp4`
- Dry run (print command, no execute): `./scripts/upscale-image.sh -n photo.jpg out/`
- JSON output (for scripting): `./scripts/upscale-image.sh -j photo.jpg out/`
- GPU check: `./scripts/check-gpu.sh`
- Fetch real test media: `./scripts/download-test-media.sh`
- Test fast (~30 s): `./scripts/test.sh`
- Test all (~2 min): `./scripts/test.sh --integration`

## Architecture
- `input/images/` → drop images here before running; gitignored
- `input/video/` → drop video here before running; gitignored
- `output/images/` → upscaled images land here; gitignored
- `output/video/` → upscaled video lands here; gitignored
- `scripts/upscale-image.sh` → image wrapper (Real-ESRGAN); exits 0/1/2/3
- `scripts/upscale-video.sh` → video wrapper (Video2X); exits 0/1/2/N
- `scripts/check-gpu.sh` → validates nvidia-smi, CUDA, torch device, Vulkan ICD
- `scripts/test.sh` → test suite; `--integration` enables batch + video source tests
- `scripts/setup.sh` → installs Real-ESRGAN venv and Video2X binary into `tools/`
- `scripts/download-test-media.sh` → fetches public-domain test media into `test-assets/`
- `test-assets/` → synthetic test fixtures (committed) + real media (gitignored)
- `img-implementation.md` → full image setup plan, risks, test plan, model reference
- `vid-implementation.md` → full video setup plan, risks, test plan, decision log
- `local-upscaling-audio.md` → audio tool survey (AudioSR, DeepFilterNet); not yet implemented

## Rules
- Always run a single-image smoke test before any long batch job
- Pre-download model weights before batch runs — never rely on auto-download mid-job
- IMPORTANT: set `--tile 512` by default; never run tilesize=0 on inputs > 2K without confirming VRAM headroom
- Output dirs must be on SSD; video pipelines create large temp files
- Face enhancement (`-F`) is opt-in only — degrades non-portrait content

## Workflow
- New tool or model: add a section to the relevant `*-implementation.md` first; get approval before coding
- Commits: `#type, what` (add/fix/doc/refactor)
- Test gate: smoke test + error path tests pass before any batch use
- Ask before changing wrapper exit-code contracts or default flag values

## Design Principles
- Local-first: no cloud upload, no external API calls
- CLI-first: no GUI dependencies; every tool composable via shell
- Fail fast: all boundary validation at script entry; errors to stderr with non-zero exit
- Model-agnostic: wrappers accept any `.pth` file path; no model names hardcoded in logic

## Out of scope
- Cloud upscaling services
- GUI tools (Upscayl, Chainner)
- Audio upscaling (`local-upscaling-audio.md` is reference only; no scripts yet)
- Anime-only workflows (Anime4K available via `-e anime4k` but not the primary path
