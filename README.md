# media-upscaler

## Project
Free, private AI upscaling for low-res images and video, entirely on your own machine (Linux, NVIDIA GPU) — an interactive TUI over composable shell scripts, for restoring old photos and footage.

## Design Principles
- Local-first: no cloud upload, no external API calls
- CLI-first: no GUI dependencies; every tool composable via shell
- Fail fast: all boundary validation at script entry; errors to stderr with non-zero exit
- Model-agnostic: wrappers accept any `.pth` file path; no model names hardcoded in logic
- Centralized calculation: shell orchestrates, Python computes — all numeric logic in one testable place (see [CONTRIBUTING.md](CONTRIBUTING.md))

## Quickstart
1. Verify GPU: `nvidia-smi` — driver must be loaded
2. Run setup: `./scripts/setup.sh`
3. Check GPU readiness: `./scripts/check-gpu.sh`
4. Drop media into `input/images/` or `input/video/`
5. **Launch TUI**: `./tool tui`  ← primary interface; all options configurable here
6. Select files, adjust preset with `[P]`, advanced options with `[o]`, then `[s]` to start
7. When the batch finishes, the output folder opens in your file manager automatically

```
╔═ media-upscaler ══════════════════════════════════════════════════════════╗
║  Preset [medium ▼]   Input [input/ ▶]                                     ║
╠══ Files ══════════════════════════════╦══ Active Job ═════════════════════╣
║ ── Images  1 done · 2 queued          ║  No active job                    ║
║  [✓] butterfly.jpg   ✓ done  11:14    ║  Press [s] to start               ║
║  [✓] great-wave.jpg  · queued ~2 m    ╠══ GPU ════════════════════════════╣
║  [✓] baby.png        · queued ~2 m    ║  Util ░░░░ 0 % · VRAM 0.6/4.0 GB  ║
║ ── Video  1 selected · 1 excluded     ╠══ Log ════════════════════════════╣
║  [✓] test-clip.mp4   · queued ~22 m   ║  waiting for job…                 ║
║  [ ] sf-1906.mp4     ○ excluded       ║                                   ║
╠═══════════════════════════════════════╩═══════════════════════════════════╣
║  Total ETA ≈ 26 m   (2 img × ~2 m + 1 vid × ~22 m)                        ║
╠═══════════════════════════════════════════════════════════════════════════╣
║ [SPACE] toggle · [a/n] all/none · [P] preset · [o] options · [s] start    ║
║ [p] pause · [c] cancel · [r] retry · [d] dir · [q] quit                   ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

Full wireframes — running state, item states, subdirectory browsing, shortcuts, presets: [`docs/tui-wireframe.md`](docs/tui-wireframe.md)

## Stack
- Bash, Python 3.12; NVIDIA driver ≥ 525, CUDA 11.8+
- Image: Real-ESRGAN Python (`RealESRGAN_x4plus`); Video: Video2X 6.4.0 AppImage (Vulkan/NCNN)
- Frame handling: FFmpeg; TUI: Textual (realesrgan venv)

## Commands
- **TUI (primary)**: `./tool tui [-q PRESET] [--input DIR]`
- Image (direct): `./scripts/upscale-image.sh input/images/photo.jpg output/images/`
- Video (direct): `./scripts/upscale-video.sh -q medium input/video/clip.mp4 output/video/clip-2x.mp4`
- Video batch: `./scripts/upscale-video.sh -q fast input/video/ output/video/`
- Video flags: `-C 300` chunked (crash-safe) · `-r` resume · `-c` calibrate · `-n` dry run · `-j` JSON output
- Presets: `-q fast|low|medium|high|xhigh|auto` (default `medium`; `-s`/`-e` override scale/engine) — table: [`docs/tui-wireframe.md`](docs/tui-wireframe.md)
- Build: `./scripts/setup.sh`
- Test all: `./scripts/test.sh --integration`
- Test fast (~30 s): `./scripts/test.sh`
- Lint: `bash -n scripts/*.sh`
- GPU check: `./scripts/check-gpu.sh`
- Fetch test media: `./scripts/download-test-media.sh`
- Perf estimate: `tools/realesrgan/venv/bin/python scripts/perf-estimate.py --video clip.mp4` (`--list-hw` for profiles)

## Architecture
- `tool` → thin dispatcher; `./tool tui` is the primary entry point
- `scripts/` → processing back-end + TUI: setup, GPU check, image/video wrappers, test suite, `tui.py`, perf/quality calc
- `docs/roadmap.md` → versions, exit criteria, work queues, hardware guidance
- `docs/tui-wireframe.md` → TUI & preset reference: full layouts, shortcuts, `-q` preset table, item states
- `docs/test-plan.md` → QA plan: benchmark assets, PSNR/SSIM bars, error paths, vetted test-media sources
- `docs/img-implementation.md` → image pipeline spec (shipped; implementation record)
- `docs/vid-implementation.md` → video pipeline spec (shipped; implementation record)
- `docs/omarchy-port.md` → living doc: multi-platform port log, open v3 stack decision
- `docs/market-gap.md` → research archive: competitive analysis that seeded the roadmap
- `docs/local-upscaling-audio.md` → research archive: audio tool survey (v4 planned; not implemented)
- `input/` → drop media here (gitignored); `output/` → results land here (gitignored)
- `test-assets/` → committed synthetic fixtures; real media gitignored
- `tools/` → engines, venvs, model weights installed by `setup.sh` (gitignored)

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

## Roadmap

| Version | Status | Theme |
|---|---|---|
| **v0** | ✅ shipped (`v0`) | Core scripts, `-q` presets, Rich monitor, perf estimator, GPU check, test suite |
| **v2-prep** | ✅ shipped (`v2-prep`) | Image `-q` presets, Textual TUI skeleton, audio stub |
| **v1** | ✅ shipped (`v1.0`) | Chunked resume, calibration probe, integrity check, VRAM auto-tile, `-q fast`, batch dirs |
| **v2** | ✅ shipped (`v2.1.0`) | Textual TUI with full CLI parity (presets, options modal, sidecar reattach, adaptive ETA, throttle warning, xhigh/dedup/interpolate) |
| **v3** | 🔵 planned | Rust rewrite — ratatui TUI, zero-copy pipeline, same feature parity |
| **v4** | 🔵 planned | Audio upscaling (RNNoise / DeepFilterNet / AudioSR) |

Status key: ✅ shipped · 🟡 in progress · 🔵 planned · ⏸ paused · ❌ dropped. Full item lists and exit criteria: [`docs/roadmap.md`](docs/roadmap.md)

## Out of scope
- Cloud upscaling services
- GUI tools (Upscayl, Chainner)
- Audio upscaling until v4 — `upscale-audio.sh` stub exists but its backends aren't installed by setup and the TUI section is inactive (`docs/local-upscaling-audio.md` is reference only)
- Anime-only workflows (Anime4K available via `-e anime4k` but not the primary path)

## License
- **MIT** — see [LICENSE](LICENSE). Provided **AS IS**, without warranty of any kind; the authors are not liable for any claim or damages arising from use.
- **Use at your own risk:** this tool runs your GPU under sustained load, may run for hours, and **overwrites files in the output directory**. Verify inputs/outputs before long batch jobs.
- **Third-party components:** media-upscaler bundles nothing — `scripts/setup.sh` fetches all engines, Python deps, and model weights onto your machine; ffmpeg/ImageMagick/the NVIDIA driver are system-provided. Their licenses (including the **GPL-3.0** video2x AppImage and this GPL build of ffmpeg) attach to your local install, not to this project's source; by running setup you fetch and inherit them directly from upstream. Full inventory with sources and SPDX licenses: [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
- **Model weights** are licensed separately from the code (BSD-3 / Apache-2.0 for the bundled defaults); confirm the upstream terms before relying on any checkpoint for commercial output.
