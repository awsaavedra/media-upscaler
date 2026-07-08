# Changelog

All notable changes to this project are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Docs restructure — README is the root navigation hub**: `readme.md` → `README.md`, rebuilt to the `.ai/readme-template.md` section order with a compact TUI wireframe in Quickstart; Architecture section now indexes every `docs/` file
- `docs/tui-wireframe.md` → "TUI & preset reference": keyboard-shortcut table synced with real bindings (added missing `P`/`o`), absorbed the `-q` preset table from the README, fixed stale `media-restore` naming
- README TODO items moved to `docs/roadmap.md` §v2.x deferred items
- `docs/test-plan.md` absorbed the vetted test-asset source list; status banners added to research and implementation docs; citation-tag noise stripped from `docs/local-upscaling-audio.md`

### Fixed
- Stale/false doc claims found by thesis audit: README "no scripts yet" for audio (the `upscale-audio.sh` stub exists, backends just aren't installable); roadmap status table said v2 "ready to tag" (v2.0 and v2.1.0 both shipped); duplicated reference-job paragraph; v4 prep task 1 marked done with the real remaining gap (`setup.sh --audio`) called out. Thesis-check record added to `docs/roadmap.md` §Current status
- Changelog link refs: added missing `[2.1.0]` compare link; `[Unreleased]` now compares from `v2.1.0`

### Removed
- `docs/test-assets-vid-img-aud.md` (merged into `docs/test-plan.md` §Test asset sources)
- `docs/omarchy-port.md` — the Omarchy port works, so the port log is history (kept in git); the still-open v3 image-stack decision (engine / Python management / video2x-on-Mac) moved to `docs/roadmap.md` §v3.0

## [2.1.0] — 2026-07-06

### Added
- **`-q auto` hardware-adaptive tier** (image + video): selects quality preset from free VRAM at runtime; video path also guards on free RAM and degrades gracefully on no-GPU boxes
- **PSNR/SSIM quality-metrics harness** (`scripts/quality-metrics.py`): full-reference image quality metrics against a ground-truth; exit 0/1/2; optional LPIPS perceptual metric
- **`assert_quality` gate in test.sh**: enforces per-tier absolute bars (butterfly ≥24 dB/0.70, baby ≥24 dB/0.60); GPU calibration baseline recorded in roadmap
- **TUI `[R]` reset**: wipes all outputs and re-queues every item for a clean re-run
- **TUI `[a]`/`[n]` scoped selection**: select-all / select-none operates within the cursor's section and subdirectory only
- **TUI `📁` file-browser subdir view**: indented file listing within subdirectory rows
- **TUI auto-open output folder** on batch completion (`xdg-open` on Linux, `open` on macOS)
- **Governance files**: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`
- **`.github/` templates**: bug-report and feature-request issue templates, pull-request template, and `config.yml` routing security and conduct reports to the private GitHub advisory channel
- **Project skills suite** (`.ai/`): ship, legal, release-engineering, governance, security, code-review, and others
- Rule 11 in `.ai/rules.md` and design principle in README: all numeric logic routes through Python (centralized, testable calc layer)

### Changed
- `THIRD_PARTY_NOTICES`: added `opencv-python`, `scikit-image`, `Pillow`, `lpips` (all permissive) explicitly to inference venv section
- `readme.md`: video preset table now includes `xhigh` and `auto` rows; architecture tree lists `quality-metrics.py`; v2 row description updated to reflect shipped features

### Fixed
- `-q auto` no-GPU fallback: `pipefail` + `set -e` previously aborted command substitution when `nvidia-smi` failed before degrading to `low`; fixed with `|| true` guard
- Python RAM snippet `int()` cast: `re.search` group returns a string; `//` division raised `TypeError` before the cast was added

---

## [2.0.0] — 2026-06-17

Full feature set + real-asset test suite.

### Added
- Image upscaling: Real-ESRGAN with `-q` presets (low/medium/high/xhigh), JPEG artifact mode, anime model (`anime_6B`), face enhancement (GFPGAN), content-based model auto-select (`-m auto`)
- Video upscaling: Video2X 6.4.0 with preset ladder (fast/low/medium/high/xhigh), NVENC re-encode for `xhigh`, dedup (`-D`), frame interpolation (`-I 2x`), thermal mode (`-T`), chunked crash-safe processing (`-C`), resume (`-r`), calibration probe (`-c`)
- Textual TUI (`tui.py`): full CLI parity — preset cycling (`P`), options modal, sidecar reattach, adaptive ETA, GPU stats panel, log pane, throttle warning (⚠ THROTTLING at ≥85°C / −15% SM clock)
- Per-job audit manifests (`OUTPUT.audit.json`) with SHA256 hashes, model params, timings
- Unified entry point (`tool upscale image|video|audio`)
- TensorRT engine stub with install guidance
- Real integration test suite: Set5/BSD100 benchmark images, prelinger-1947 + sf-1906 GPU video tests (real film grain)

---

## [v2-prep] — 2026-06-13

### Added
- Sidecar progress JSON writers; TUI reattach on startup and every 5 s
- Adaptive ETA (measured fps replaces hardware-profile seed)
- Preset cycling in TUI; options modal for all script flags
- Image `-q` preset: low/medium/high (unified with video knob)
- Audio stub (`upscale-audio.sh`)
- Textual TUI skeleton (`tui.py`)

---

## [1.0.0] — 2026-06-11

### Added
- `-q fast` preset: `realesr-animevideov3` (SRVGGNet compact, fastest GPU path)
- Chunked processing (`-C SECS`) + resume (`-r`): crash-safe for long encodes
- Calibration probe (`-c`): 30-frame sample → measured fps + ETA before full run
- Post-mux integrity check: duration, frame count, file-size gate
- Temp-disk preflight: estimates output size, aborts if insufficient space
- VRAM auto-tile: adjusts tile size for inference from free VRAM at runtime
- Batch video directory mode: recursive walk, skip existing outputs, summary report

---

## [0.0.0] — 2026-06-09

### Added
- `-q` presets (medium/high), dry run, JSON output, GPU check
- Rich TUI monitor (frame/fps/ETA/VRAM/temp/clock)
- Hardware throughput estimator (`perf-estimate.py`) with hardware profiles
- Test suite (fast + integration modes)
- Setup/teardown scripts, gitignore, project scaffolding

[Unreleased]: https://github.com/awsaavedra/media-upscaler/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/awsaavedra/media-upscaler/compare/v2.0...v2.1.0
[2.0.0]: https://github.com/awsaavedra/media-upscaler/compare/v1.0...v2.0
[1.0.0]: https://github.com/awsaavedra/media-upscaler/compare/v2-prep...v1.0
[v2-prep]: https://github.com/awsaavedra/media-upscaler/compare/v0...v2-prep
[0.0.0]: https://github.com/awsaavedra/media-upscaler/releases/tag/v0
