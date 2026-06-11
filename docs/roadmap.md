# Roadmap — version tags

Derived from [market-gap.md](market-gap.md) (2026-06-09). Focus order: 1. usability, 2. efficient image/video processing; TUI/feedback/setup fold into usability.

## Current status (2026-06-11)

| Version | Tag | Status | Blocking |
|---|---|---|---|
| **v0** | `v0` | ✅ shipped | — |
| **v2-prep** | `v2-prep` | ✅ shipped | — |
| **v1** | `v1.0` | ✅ shipped | — |
| **v2** | — | 🟡 TUI in progress | throttle warning; TensorRT; NVENC; duplicate-frame skip; remaining v2 features |
| **v3** | — | 🔵 planned | v2 must ship first |
| **v4** | — | 🔵 planned | v3 must ship first |

**v1 done as of 2026-06-11:** `-q fast` preset (`realesr-animevideov3`), chunked processing + `-r` resume, calibration probe (`-c`), post-mux integrity check, temp-disk preflight, VRAM auto-tile for images, batch video directory mode. Exit bar (`≤ 10 h` reference job on RTX 3050 Mobile) and throttle warning TUI remain before tagging `v1.0`.

**v2 done as of 2026-06-11:** Textual TUI (`tui.py`) with full CLI parity — preset cycling, options modal (all script flags), sidecar reattach, adaptive ETA, GPU stats panel, log pane. Tagged `v2-prep`; TUI options modal landed one commit after that tag. Remaining v2 items listed in the v2 section below.

Reference job for all targets below: **1 hour 854×480 @ 25 fps → 1920×1080** (90,000 frames), path = AI 2× → 1708×960 → lanczos 1.125× → 1080p. Integer-scale engines can't do 2.25× directly; 4×-then-downscale is ~6× the work for discarded detail.

Reference job for all targets below: **1 hour 854×480 @ 25 fps → 1920×1080** (90,000 frames), path = AI 2× → 1708×960 → lanczos 1.125× → 1080p. Integer-scale engines can't do 2.25× directly; 4×-then-downscale is ~6× the work for discarded detail.

## v0 (current, baseline)

Shipped: `-q` presets, Rich TUI (frame/fps/ETA/VRAM/temp/clock), perf estimator with hardware profiles, dry-run, JSON output, GPU check, test suite.

Verified stable 2026-06-09: `test.sh --integration` 32/32 (incl. GPU medium encode, 2.83 fps @ 320×180), `check-gpu.sh` 4/4, `bash -n` clean, Vulkan device 0 = RTX 3050 (wrapper default targets dGPU correctly).

Measured on RTX 3050 Mobile (4 GB):

| Preset | fps @ 854×480 | Reference job |
|---|---|---|
| `medium` (RealCUGAN 2×, NCNN/Vulkan) | ~0.46 | **~55 h** |
| `high` (Real-ESRGAN 4×) | ~0.08 | ~13 days (wrong tool for SD→HD) |

Two problems: a 55 h job has no resume (one crash = total loss), and the NCNN/Vulkan path uses shader FP16 — Tensor cores idle, still-image-grade models doing video work.

## v1.0 — reference job survivable, then overnight

Exit criteria: reference job completes **≤ 10 h** on RTX 3050 Mobile, survives `kill -9` / power loss losing ≤ one chunk, and never needs babysitting.

### Usability & survivability

- **Batch folder input — zero per-file invocation** ✓ done — `upscale-image.sh` (pre-existing batch mode) + `upscale-video.sh` now detects directory INPUT, recurses self per file, mirrors tree, skips done (output exists), continue-on-error, end-of-run summary. Compose: `upscale-video.sh -q fast input/video/ output/video/`.
- **Chunked processing + `--resume`** ✓ done — `upscale-video.sh -C 300` segments → upscales per chunk → concats; per-chunk `out_N.json` sidecar (pending/running/done/failed); `-r` resumes by skipping chunks with existing output. Acceptance: kill mid-job, re-run with same `-C N -r`, lose ≤ 1 chunk.
- **Progress sidecar JSON + TUI re-attach** ✓ done (v2-prep) — both scripts write `{output}.progress.json`; TUI polls on startup and every 5 s.
- **Calibration probe → trustworthy ETA** ✓ done — `upscale-video.sh -c` extracts 30 frames from 30% seek point, upscales with selected engine, prints measured fps + ETA; warns if disk short.
- **Post-mux integrity check** ✓ done — runs after every encode: duration drift ≤ 100 ms, frame count diff ≤ 2, A/V sync ≤ 40 ms; `integrity_ok` field in JSON output.
- **Temp-disk preflight** ✓ done — estimates output KB from bitrate × duration × scale²; errors if insufficient free space; 50 GB soft warning remains.
- **Throttle warning in TUI** — flag sustained SM-clock drop at temp ≥ threshold (data already polled). *(TUI work — deferred)*

### Efficiency (image/video processing)

- **`-q fast` preset: compact video model** ✓ done — `upscale-video.sh -q fast` uses `realesr-animevideov3` (SRVGGNet compact) via video2x. Benchmark at 854×480 still needed to validate ≤ 10 h exit bar; if < 2.5 fps, pull TensorRT from v2.
- **VRAM probe → auto tile + FP16 defaults** ✓ done (tile) — `upscale-image.sh` queries `nvidia-smi --query-gpu=memory.free` and maps to tile (200/4 GB, 300/6 GB, 400/8 GB, 512/8–12 GB, 600/12+ GB); skipped if `-t` explicit. FP16: deferred — Real-ESRGAN inference script handles precision internally.

## v2.0 — differentiation

Exit criteria: reference job **≤ 4 h** on 3050 Mobile; feature set matches the "Your Target" column of the market-gap feature matrix.

### Simplified quality presets

Image and video expose a single `-q` knob. Raw flags (`-s`, `-m`, `-e`, etc.) remain as overrides — same pattern as the existing video `-q` + `-s`/`-e` overrides. Audio upscaling is deferred to v4.

**Image presets** (`-q` flag, new — mirrors video convention):

| Preset | Scale | Model | Face | Tile | Notes |
|---|---|---|---|---|---|
| `low` | 2× | RealESRGAN_x2plus | no | 256 | Fast; ~¼ VRAM; bulk preview runs |
| `medium` | 4× | RealESRGAN_x4plus | no | 512 | Default; balanced quality |
| `high` | 4× | RealESRGAN_x4plus | yes (GFPGAN) | 512 | Best quality for portraits/archival |
| `ultrahigh` | 4× | RealESRGAN_x4plus | yes | 0 (auto) | Max quality; targets 4K output from HD source |

**Video presets** (extends existing `low/medium/high`, adds `ultrahigh`):

| Preset | Engine | Scale | Encode | Notes |
|---|---|---|---|---|
| `low` | ffmpeg lanczos | 2× | libx264 | CPU only; seconds per clip |
| `medium` | RealCUGAN | 2× | libx264 | Default; AI-enhanced |
| `high` | Real-ESRGAN | 4× | libx264 | Best quality |
| `ultrahigh` | Real-ESRGAN | 4× | NVENC (blocked until NVENC fix below) | Max quality; targets 4K output |

### Python Textual TUI — progress bars and ETA for all 3 media types

Full layout wireframe and widget mapping: **[docs/tui-wireframe.md](tui-wireframe.md)**

Replace `scripts/tui-monitor.py` (Rich, video-only, output-only) with a full [Textual](https://github.com/Textualize/textual) app. Panels:

- **Job queue panel** — add jobs via form or `tool upscale … --queue`; shows media type tag, preset, input path, status.
- **Default selection rules** — applied at startup: images (all unupscaled `[✓]`, already-done shown but skipped); video (first unupscaled item only `[✓]`, rest start unchecked — videos are long, batch-all by default would silently queue hours); audio (all unupscaled `[✓]`). "Already upscaled" detected by output file existence, no separate state file.
- **Per-job progress bar + ETA** — 0–100% bar, live throughput metric, adaptive ETA for image and video jobs:
  - Image: files/s (or tiles/s for large single files)
  - Video: fps (port from current `tui-monitor.py`)
  - (Audio ETA deferred to v4)
- **Persistent aggregate ETA** — always visible in the bottom status bar; `Total ETA = Σ est(item)` for all checked, not-yet-done items. Updates immediately on every checkbox toggle so the user sees the cost of adding or removing items before starting. Switches to `Elapsed X m · Remaining ≈ Y m` once a run is active.
- **GPU stats panel** — temp, VRAM, SM clock, throttle flag (port GPU poller from `tui-monitor.py`).
- **Log pane** — last N stderr lines from the active job.
- **Keyboard shortcuts** — `p` pause, `c` cancel, `r` reattach, `q` quit, `SPACE` toggle item (ETA updates instantly).

**Every CLI flag and argument permutation must be reachable from the TUI** — no flag available on the command line absent or non-configurable in the TUI. Single entry point: `tool tui`.

Acceptance: all v1 TUI data visible; every CLI option exposed; attach/detach via sidecar JSON; no Rich import remaining in TUI path.

**Adaptive ETA design** (extends current `tui-monitor.py` pattern to all 3 media types):

- Seed from `perf-estimate.py` hardware profile at job start → instant first estimate.
- Update every 5 s from measured throughput → converges to ±10 % accuracy within the first 5 % of the job.
- If v1 calibration probe is available, its measured fps replaces the hardware-profile seed immediately.

All three scripts write `{output}.progress.json` sidecar (same protocol as v1 video); TUI polls it.

### Remaining v2 features

- **TensorRT / PyTorch FP16 backend with frame batching** — use Tensor cores instead of NCNN shader FP16; expected 2–4× on RTX 30-series. Larger lift; keep NCNN as fallback. Candidate for promotion to v1 if `-q fast` misses the exit bar (see v1).
- **NVENC encode** — blocked inside Video2X: bundled AppImage libav fails with error -22 on `h264_nvenc` (verified 2026-06-09, with and without `--pix-fmt yuv420p`). System ffmpeg has h264/hevc/av1_nvenc, so the path is newer AppImage, or lossless intermediate + system-ffmpeg encode. Minor lever (~1.2×), hence v2.
- **Duplicate-frame skip** — mpdecimate-style dedup before inference, reuse upscaled frame via mapping; 1.2–2× on low-motion content.
- **RIFE frame interpolation** — `--interpolate 2x`.
- **`--thermal-mode conservative|balanced|performance`** — act on throttle data, not just warn.
- **Content-based model auto-select** — anime vs photographic vs text-heavy detection → model recommendation.
- **Unified command grammar** — `tool upscale image|video|audio --input … --output …` front-end over existing scripts.
- **Per-job audit manifest** — input/output hashes, model, tile, precision, per-stage timings, warnings. (Batch folder input itself is v1; this adds the audit trail + glob patterns outside `input/`.)

### v2 prep tasks (can land in v1.x)

These are prerequisites for the unified TUI but are small enough to ship early:

1. Add `-q low|medium|high|ultrahigh` to `upscale-image.sh`. ✓ done
2. Build Python Textual TUI app (`tool tui` entry point). ✓ done — `scripts/tui.py`, entry point `tool tui`.
3. Implement sidecar JSON writer in `upscale-image.sh` and `upscale-video.sh`; implement detach/reattach in TUI. **Not yet started** — see "TUI: what's still needed" below.

### TUI: what's still needed

The initial TUI (`scripts/tui.py`, `tool tui`) is complete for the core interactive layer: layout, scanning, default selection, per-section buttons, aggregate ETA, all keyboard shortcuts, job execution, progress parsing, GPU polling, and log pane. The following items remain before the spec acceptance criteria are fully met.

**Blocking for reattach / session persistence**

- `upscale-image.sh`: add `{output}.progress.json` sidecar writer. Write at job start (`status: running, pct: 0`), update on each "Testing N" line (`pct: N/total * 100`, `throughput: tiles/s`), write on completion (`status: done`) or failure (`status: failed`), then delete on clean exit. Format matches `upscale-audio.sh` stub: `{"status":…,"pct":…,"elapsed_s":…,"input_s":…,"processed_s":…,"throughput_ratio":…}`.
- `upscale-video.sh`: same sidecar writer. Update on each `frame=N/M` line (`pct`, `fps`, `remaining`); video's existing progress-to-stderr path makes this straightforward.
- `tui.py` startup: on `on_mount`, after scanning, check each item's `output_path + ".progress.json"`. If it exists and `status == "running"`, mark that item `▶ active` and start polling its sidecar instead of spawning a new subprocess. This is step 5 of the wireframe startup spec.
- `tui.py` sidecar poller: add a second `set_interval(5, _poll_sidecars)` that reads each active item's sidecar and calls `_refresh_active_panel`. Needed for the detached-process case (job still running from a previous TUI session).

**Adaptive ETA refinement**

- `tui.py`: after `_after_job` completes successfully, compute `actual_seconds = time.time() - job_start_time` for that item. Call `item.record_rate(actual_rate)` and then update `est_seconds` on all remaining same-type, same-preset queued items to the running average. The `_rate_sum`/`_rate_n` fields on `MediaItem` are already present; the update logic in `_after_job` is not. The ETA aggregate will then converge across a batch rather than staying fixed at seed values.

**Progress parsing: needs validation against real runs**

- `parse_image_progress()` targets Real-ESRGAN's `Testing N name` and `Tile K/M` stdout lines. These have not been tested against actual inference output. The regexes may need adjustment once a real run is observed — in particular, the tile counter line format may vary between Real-ESRGAN versions.
- `parse_video_progress()` targets video2x's `frame=N/M (PCT%); fps=X; elapsed=MM:SS; remaining=HH:MM:SS` format (ported from `tui-monitor.py`). The current TUI runs the video script non-interactively (no TTY), which means video2x output goes to stdout without the `tui-monitor.py` intermediary — the raw format needs to be confirmed at least once live before this is trusted.

**Preset and input-dir interactivity**

- The header bar `Preset [medium ▾]` is currently a plain `Static` — not interactive. Add a `Select` widget (or cycle-on-click with `Label`) so the preset can be changed mid-session. When changed: re-apply ETA seeds to all queued items and update the aggregate ETA bar. Any actively-running job keeps its original preset. File: `tui.py` `compose()` and a new `action_change_preset()`.
- `action_change_dir()` currently rescans the same `_input_dir`. It should prompt for a new path first. Textual has no built-in file picker; the minimal path is an `Input` widget pushed as an inline modal that captures a typed path, then calls `scan_all()` with the new root.

**Section header counts during active job**

- `_refresh_active_panel()` updates the active job panel and ETA bar but does not call `_update_section_counts()`. The "1 active" badge in the section header therefore only updates at job boundaries. Add `self._update_section_counts()` to `_refresh_active_panel()` (one line).

**Retire `tui-monitor.py`**

- `upscale-video.sh` still pipes to `scripts/tui-monitor.py` in TTY mode. Once the Textual TUI is the primary path and the sidecar writers are in place, remove the `tui-monitor.py` pipe from `upscale-video.sh` and delete `tui-monitor.py`. Acceptance: `grep -r 'tui-monitor' scripts/` returns nothing.

### Tradeoffs considered

**TUI framework**

| Option | Pros | Cons | Decision |
|---|---|---|---|
| **Textual** | Interactive; job queue; keyboard nav; reactive CSS layouts; actively maintained; built on Rich | ~5 MB extra dep; CSS DSL learning curve | **Chosen** — pause/cancel/queue require interaction |
| Rich (current) | Already installed; zero new deps | Output-only; no interaction possible | Kept for non-TUI output paths (JSON, log) |
| urwid | Mature; widely deployed | More boilerplate; no CSS layouts; less active | Rejected — worse DX, same capability |
| curses | Most portable; stdlib | Raw; no layout abstractions; painful multi-panel | Rejected — wrong complexity/portability tradeoff |

**Preset design**

| Option | Pros | Cons | Decision |
|---|---|---|---|
| **Quality tiers** | Bundles optimal engine + model + scale per use case; one-knob UX | Hides raw params; power users need overrides (provided) | **Chosen** |
| Resolution targets (480p/720p/1080p/4K output) | User knows exact output resolution | Dynamic scale per source; breaks for varied input sizes | Rejected |
| Scale-factor tiers (2×/4×/8×) | Simple to reason about | 8× is near-useless (16 K from HD input); doesn't change engine | Rejected |

**ETA computation**

| Method | Accuracy | First estimate | Decision |
|---|---|---|---|
| Hardware profile lookup (`perf-estimate.py`) | ±50 % | Instant | Seed only |
| Calibration probe (30 frames, v1) | ±20 % | ~30 s overhead | Replaces seed when available |
| **Adaptive live** | Converges to ±10 % within first 5 % | Instant (profile seed) | **Chosen for TUI** |

## v3.0 — Rust rewrite (primary goal: speed)

Exit criteria: reference job measurably faster than v2 on identical hardware; full feature parity; all integration tests pass against the Rust binary; Python scripts retired.

Primary motivation is throughput — Rust eliminates Python interpreter overhead, enables zero-copy buffer passing to inference engines, and opens direct CUDA/Vulkan interop without subprocess boundaries. The Python codebase is the reference implementation for behavior; v3 is a port, not a redesign — no new features until parity is confirmed.

- **ratatui TUI** — replace Textual with [ratatui](https://github.com/ratatui-org/ratatui): same panels (job queue, progress, GPU stats, log), same sidecar-JSON attach protocol, same keyboard shortcuts. **Every CLI flag and argument permutation must be reachable from the TUI** — parity with the v2 Textual TUI is the minimum bar; any flag added to the CLI must have a corresponding TUI control. Single binary entry point. Acceptance: feature-for-feature parity with the Textual TUI including full CLI surface; no Python runtime dependency.
- **Core pipeline in Rust** — port chunked processing, resume logic, batch folder sweep, progress sidecar writer, preflight checks (disk, VRAM probe), integrity checker, and perf estimator to Rust. FFI or subprocess calls to NCNN/TensorRT stay; no rewrite of inference engines.
- **CLI parity** — same flags and exit codes as v2 Python CLI; shell scripts that consumed v2 output work unchanged.
- **Test suite port** — `scripts/test.sh` integration tests rewritten to invoke the Rust binary; same acceptance criteria.
- **Dependency audit** — `Cargo.lock` committed; no yanked crates; `cargo audit` clean at ship.

## v4.0 — audio upscaling

Exit criteria: all three media types fully supported with `-q` presets and TUI integration; audio jobs appear in the checklist with progress bars and ETA.

### Audio presets (`upscale-audio.sh` — `low/medium/high`)

| Preset | Backend | Output SR | GPU | Notes |
|---|---|---|---|---|
| `low` | RNNoise | passthrough | no | Noise gate only; CPU; near-instant |
| `medium` | DeepFilterNet | passthrough | optional | Speech + background noise reduction |
| `high` | AudioSR | 48 kHz | yes | Full neural SR; ~10× realtime on 3050 |

AudioSR is the only OSS option for true audio super-resolution; the tier design lets users skip the GPU dep unless they want `high`.

### Backend tradeoffs

| Backend | Quality | Speed | GPU | Dep size | Role |
|---|---|---|---|---|---|
| RNNoise | Noise gate | Near-instant | No | ~200 KB | `low` |
| DeepFilterNet | Speech + bg noise | 2–5× realtime | Optional | ~50 MB | `medium` |
| AudioSR | Neural SR 48 kHz | ~10× realtime on 3050 | Yes | ~500 MB | `high` |

### Prep tasks

1. Complete `scripts/upscale-audio.sh` stub (flag parsing, sidecar JSON, exit codes) — stub landed as v2 prep; wire real backends here.
2. Add AudioSR + DeepFilterNet install to `scripts/setup.sh` behind `--audio` opt-in flag (off by default until v4).
3. Add audio section to Textual TUI checklist with per-item ETA (seconds-of-audio processed / elapsed second).
4. Extend `perf-estimate.py` with audio hardware profiles.

---

## Hardware: squeeze vs buy

Software first — v1+v2 levers stack to roughly **5–10×** on owned hardware before any purchase. Buy only when the job class changes:

| Trigger | Buy | Why |
|---|---|---|
| Routine `high`/4× archival on hour-long files | used RTX 3090 (24 GB) | VRAM is the binding constraint (the `--tile 512` rule exists because of 4 GB), ~3–5× throughput, no tiling |
| Several files/day, SD→HD | RTX 4070 Super (12 GB) | ~2.5–3×, current-gen efficiency |
| 1080p→4K hour-long content | 16–24 GB class | 5× input pixels of the reference job; even squeezed 3050 is back to ~30+ h |

Caveats: estimator's geometric-mean model flatters high-bandwidth cards (5090 "28×" is theoretical; NCNN path can't use its Tensor cores either); 3050 Mobile is a laptop part — a desktop card implies a new machine, not an upgrade.
