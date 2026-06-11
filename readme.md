# media-restoration

## Project
AI-upscale low-res images and video entirely on your own machine (Ubuntu, RTX 3050–3060 Ti, 32 GB RAM) — a free, private CLI alternative to cloud/subscription upscalers for restoring old photos and footage.

## Quickstart
1. Verify GPU: `nvidia-smi` — driver must be loaded
2. Run setup: `./scripts/setup.sh`
3. Check GPU readiness: `./scripts/check-gpu.sh`
4. Drop media into `input/images/` or `input/video/`
5. Upscale image: `./scripts/upscale-image.sh input/images/photo.jpg output/images/`
6. Upscale video: `./scripts/upscale-video.sh -q medium input/video/clip.mp4 output/video/clip-2x.mp4`

## Stack
- Bash, Python 3.12; NVIDIA driver ≥ 525, CUDA 11.8+
- Image: Real-ESRGAN Python (`RealESRGAN_x4plus`); Video: Video2X 6.4.0 AppImage (Vulkan/NCNN)
- Frame handling: FFmpeg; TUI: `rich` (realesrgan venv)

## Commands
- Dev (image): `./scripts/upscale-image.sh input/images/photo.jpg output/images/`
- Dev (video): `./scripts/upscale-video.sh -q medium input/video/clip.mp4 output/video/clip-2x.mp4`
- Build: `./scripts/setup.sh`
- Test all: `./scripts/test.sh --integration`
- Test fast (~30 s): `./scripts/test.sh`
- Lint: `bash -n scripts/*.sh`
- Dry run: `./scripts/upscale-video.sh -n -q high clip.mp4 out.mp4`
- JSON output: `./scripts/upscale-video.sh -j clip.mp4 out.mp4`
- GPU check: `./scripts/check-gpu.sh`
- Fetch test media: `./scripts/download-test-media.sh`
- Perf estimate: `tools/realesrgan/venv/bin/python scripts/perf-estimate.py --video clip.mp4`
- List hardware profiles: `tools/realesrgan/venv/bin/python scripts/perf-estimate.py --list-hw`

### Video quality presets (`-q`)
| Preset | Engine | Scale | GPU | Speed | Quality |
|---|---|---|---|---|---|
| `low` | ffmpeg lanczos | 2× | no | ~seconds | smooth interpolation, no AI detail |
| `medium` *(default)* | RealCUGAN | 2× | yes | ~2 min/10 s (320×180) | AI-enhanced, good balance |
| `high` | Real-ESRGAN | 4× | yes | ~2 h/30 s | best quality, highest VRAM use |

Use `-s` and `-e` to override scale or engine individually (e.g. `-q low -s 4` for ffmpeg at 4×).

## Architecture
```
├── scripts/
│   ├── setup.sh                        # installs Real-ESRGAN venv + Video2X into tools/
│   ├── check-gpu.sh                    # validates nvidia-smi, CUDA, torch device, Vulkan ICD
│   ├── upscale-image.sh                # image wrapper (Real-ESRGAN); exits 0/1/2/3
│   ├── upscale-video.sh                # video wrapper (Video2X, -q presets); exits 0/1/2/N
│   ├── test.sh                         # test suite; --integration enables full tests
│   ├── download-test-media.sh          # fetches public-domain test media → test-assets/
│   ├── perf-estimate.py                # hardware throughput estimator; --video/--target/--list-hw
│   └── tui-monitor.py                  # Rich TUI progress monitor; --frames N
├── docs/
│   ├── roadmap.md                      # v1/v2/v3 roadmap; reference-job math, hardware guidance
│   ├── market-gap.md                   # market gap analysis and background research
│   ├── img-implementation.md           # image setup: plan, risks, test plan, model reference
│   ├── vid-implementation.md           # video setup: plan, risks, test plan, decision log
│   ├── local-upscaling-audio.md        # audio tool survey (AudioSR, DeepFilterNet); not implemented
│   └── test-assets-vid-img-aud.md      # test asset sources and guidelines
├── input/
│   ├── images/                         # drop images here before running; gitignored
│   └── video/                          # drop video here before running; gitignored
├── output/
│   ├── images/                         # upscaled images land here; gitignored
│   └── video/                          # upscaled video lands here; gitignored
├── test-assets/
│   ├── images/                         # synthetic image fixtures (committed)
│   └── videos/                         # synthetic video fixtures (committed); real media gitignored
└── tools/                              # installed by setup.sh; gitignored
```

## Rules
- Always run a single-image smoke test before any long batch job
- Pre-download model weights before batch runs — never rely on auto-download mid-job
- IMPORTANT: set `--tile 512` by default; never run tilesize=0 on inputs > 2K without confirming VRAM headroom
- Output dirs must be on SSD; video pipelines create large temp files
- Ask before changing wrapper exit-code contracts or default flag values

## Workflow
- New tool or model: add a section to the relevant `docs/*-implementation.md` first; get approval before coding
- Commits: `#type, what; what` — type is add/fix/doc/refactor/stabilize/edit
- Test gate: smoke test + error path tests pass before any batch use
- When unsure, present alternatives; user chooses

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
