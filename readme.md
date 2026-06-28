# media-restoration

## Project
AI-upscale low-res images and video entirely on your own machine (Ubuntu, RTX 3050–3060 Ti, 32 GB RAM) — a free, private alternative to cloud/subscription upscalers for restoring old photos and footage. Primary interface is an interactive TUI; shell scripts are the processing back-end.

## Roadmap

| Version | Status | Theme |
|---|---|---|
| **v0** | ✅ shipped (`v0`) | Core scripts, `-q` presets, Rich monitor, perf estimator, GPU check, test suite |
| **v2-prep** | ✅ shipped (`v2-prep`) | Image `-q` presets, Textual TUI skeleton, audio stub |
| **v1** | ✅ shipped (`v1.0`) | Chunked resume, calibration probe, integrity check, VRAM auto-tile, `-q fast`, batch dirs |
| **v2** | 🟡 in progress | Textual TUI with full CLI parity (presets, options modal, sidecar reattach, adaptive ETA) — pending: throttle warning, TensorRT, NVENC, dedup |
| **v3** | 🔵 planned | Rust rewrite — ratatui TUI, zero-copy pipeline, same feature parity |
| **v4** | 🔵 planned | Audio upscaling (RNNoise / DeepFilterNet / AudioSR) |

Full item lists and exit criteria: [`docs/roadmap.md`](docs/roadmap.md)

## Quickstart
1. Verify GPU: `nvidia-smi` — driver must be loaded
2. Run setup: `./scripts/setup.sh`
3. Check GPU readiness: `./scripts/check-gpu.sh`
4. Drop media into `input/images/` or `input/video/`
5. **Launch TUI**: `./tool tui`  ← primary interface; all options configurable here
6. Select files, adjust preset with `[P]`, advanced options with `[o]`, then `[s]` to start
7. When the batch finishes, the output folder opens automatically in your file manager (`xdg-open` on Linux, `open` on macOS)

Subdirectories under `input/images/` show as `📁` folders with their files indented, like a file browser; `[a]`/`[n]` select within the folder your cursor is in.

### TUI keyboard shortcuts
| Key | Action |
|---|---|
| `↑ / ↓` | Navigate file list |
| `SPACE` | Toggle file selection; ETA updates instantly |
| `a / n` | Select all / none — **scoped to the cursor's section & subdirectory** |
| `t` | Invert selection |
| `r` | Retry all failed |
| `f` | Force re-run a done item |
| `R` | Reset — wipe all outputs and re-queue every item for a clean re-run |
| `s` | Start batch |
| `p` | Pause / resume active job |
| `c` | Cancel active job |
| `P` | Cycle quality preset (low → medium → high → xhigh) |
| `o` | Options — set scale, model, format, tile, face, engine overrides |
| `d` | Change input directory |
| `q` | Quit |

### Direct CLI (back-end scripts, power users)

## Stack
- Bash, Python 3.12; NVIDIA driver ≥ 525, CUDA 11.8+
- Image: Real-ESRGAN Python (`RealESRGAN_x4plus`); Video: Video2X 6.4.0 AppImage (Vulkan/NCNN)
- Frame handling: FFmpeg; TUI: Textual (realesrgan venv)

## Commands
- **TUI (primary)**: `./tool tui [-q PRESET] [--input DIR]`
- Image (direct): `./scripts/upscale-image.sh input/images/photo.jpg output/images/`
- Video (direct): `./scripts/upscale-video.sh -q medium input/video/clip.mp4 output/video/clip-2x.mp4`
- Video batch: `./scripts/upscale-video.sh -q fast input/video/ output/video/`
- Video chunked (crash-safe): `./scripts/upscale-video.sh -q medium -C 300 input/video/clip.mp4 output/video/clip.mp4`
- Video resume: `./scripts/upscale-video.sh -q medium -C 300 -r input/video/clip.mp4 output/video/clip.mp4`
- Video calibrate: `./scripts/upscale-video.sh -q medium -c input/video/clip.mp4 output/video/clip.mp4`
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
| `fast` | realesr-animevideov3 | 2× | yes | ≥9 fps @320×180 | SRVGGNet compact; fastest AI path |
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
│   ├── tui-monitor.py                  # legacy Rich monitor (video-only, superseded by tui.py)
│   └── tui.py                          # Textual TUI — primary interface; entry point: ./tool tui
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

## TODO
- **Test setup/teardown should leave only images for visual review.** After a run, `output/` keeps `.progress.json` and `.audit.json` sidecars beside the media; `teardown.sh` only clears `output/images/test-results/`. Add a sweep (or have scripts delete `.progress.json` on clean exit) so the only generated artifacts left to eyeball are the images themselves (png/jpg/webp).
- **Keyboard preset picker (deferred).** `P` currently cycles `low → medium → high → xhigh` (works, discoverable via footer + log). A `PresetModal` number-key picker was built but reverted: it renders on open yet throws `AttributeError: 'str' object has no attribute 'render_strips'` on a later/teardown render under Textual 8.2.7 (Help/Options/Dir modals are unaffected — root cause not yet isolated). Revisit when the TUI snapshot harness below lands, or after a Textual bump.
- **Investigate a high-fidelity TUI test harness.** Current TUI coverage is unit-level (`scripts/test_tui.py`: pure helpers + headless `run_test` smoke) plus a manual plan in `test.sh` (§31–48). Evaluate snapshot/interaction harnesses to catch visual + reactive regressions automatically: `pytest-textual-snapshot` (SVG snapshot diffs), Textual `Pilot` (scripted key/click drives), and terminal-capture tools (e.g. `tuitest`/`pexpect`). Goal: assert "every action produces a visible reaction" (rules.md #10) in CI without a GPU.

## Out of scope
- Cloud upscaling services
- GUI tools (Upscayl, Chainner)
- Audio upscaling (`docs/local-upscaling-audio.md` is reference only; no scripts yet)
- Anime-only workflows (Anime4K available via `-e anime4k` but not the primary path)
