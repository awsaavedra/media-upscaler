# media-restoration

## Project
Local CLI upscaling pipeline for images and video; runs fully on-device (Ubuntu, RTX 3050–3060 Ti, 32 GB RAM).

## Quickstart
1. Verify GPU: `nvidia-smi` — driver must be loaded
2. Run setup: `./scripts/setup.sh` — installs Real-ESRGAN venv and Video2X binary under `tools/`
3. Check GPU readiness: `./scripts/check-gpu.sh`
4. Drop media into `input/images/` or `input/video/`
5. Upscale: `./scripts/upscale-image.sh input/images/photo.jpg output/images/` or `./scripts/upscale-video.sh input/video/clip.mp4 output/video/clip-2x.mp4`
6. Estimate performance on target hardware: `tools/realesrgan/venv/bin/python scripts/perf-estimate.py --video input/video/clip.mp4`
7. Monitor live progress: TUI activates automatically when a terminal is attached to step 5

## Stack
- Bash, Python 3.12; NVIDIA driver ≥ 525, CUDA 11.8+
- Image: Real-ESRGAN Python (`RealESRGAN_x4plus`); Video: Video2X 6.4.0 AppImage (Vulkan/NCNN)
- Frame handling: FFmpeg; TUI: `rich` (realesrgan venv)

## Commands
- Setup: `./scripts/setup.sh`
- Dev (image): `./scripts/upscale-image.sh input/images/photo.jpg output/images/`
- Dev (video): `./scripts/upscale-video.sh -q medium input/video/clip.mp4 output/video/clip-2x.mp4`
- Test fast (~30 s): `./scripts/test.sh`
- Test all (~2 min): `./scripts/test.sh --integration`
- Lint: `bash -n scripts/*.sh` (syntax check; no shellcheck installed)
- Dry run: `./scripts/upscale-video.sh -n -q high clip.mp4 out.mp4`
- JSON output: `./scripts/upscale-video.sh -j clip.mp4 out.mp4`
- GPU check: `./scripts/check-gpu.sh`
- Fetch test media: `./scripts/download-test-media.sh`
- Perf estimate: `tools/realesrgan/venv/bin/python scripts/perf-estimate.py --video clip.mp4`
- List hardware profiles: `tools/realesrgan/venv/bin/python scripts/perf-estimate.py --list-hw`

### Video quality presets (-q)
| Preset | Engine | Scale | GPU | Speed | Quality |
|---|---|---|---|---|---|
| `low` | ffmpeg lanczos | 2× | no | ~seconds | smooth interpolation, no AI detail |
| `medium` *(default)* | RealCUGAN | 2× | yes | ~2 min/10 s (320×180); ~20 min/30 s (640×480) | AI-enhanced, good balance |
| `high` | Real-ESRGAN | 4× | yes | ~2 h/30 s | best quality, highest VRAM use |

Use `-s` and `-e` to override scale or engine individually (e.g. `-q low -s 4` for ffmpeg at 4×).

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
- `scripts/perf-estimate.py` → hardware throughput estimator; `--video`, `--target`, `--list-hw`
- `scripts/tui-monitor.py` → Rich TUI progress monitor; pipe video2x output through it with `--frames N`
- `test-assets/` → synthetic test fixtures (committed) + real media (gitignored)
- `docs/img-implementation.md` → image setup plan, risks, test plan, model reference
- `docs/vid-implementation.md` → video setup plan, risks, test plan, decision log
- `docs/local-upscaling-audio.md` → audio tool survey (AudioSR, DeepFilterNet); not yet implemented
- `docs/test-assets-vid-img-aud.md` → test asset sources and guidelines
- `docs/market-gap.md` → market gap analysis and background research

## Rules
- Always run a single-image smoke test before any long batch job
- Pre-download model weights before batch runs — never rely on auto-download mid-job
- IMPORTANT: set `--tile 512` by default; never run tilesize=0 on inputs > 2K without confirming VRAM headroom
- Output dirs must be on SSD; video pipelines create large temp files
- Face enhancement (`-F`) is opt-in only — degrades non-portrait content

## Workflow
- New tool or model: add a section to the relevant `docs/*-implementation.md` first; get approval before coding
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
- Audio upscaling (`docs/local-upscaling-audio.md` is reference only; no scripts yet)
- Anime-only workflows (Anime4K available via `-e anime4k` but not the primary path)
