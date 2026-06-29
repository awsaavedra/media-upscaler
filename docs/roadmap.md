# Roadmap — version tags

Derived from [market-gap.md](market-gap.md) (2026-06-09). Focus order: 1. usability, 2. efficient image/video processing; TUI/feedback/setup fold into usability.

## Current status (2026-06-16)

| Version | Tag | Status | Blocking |
|---|---|---|---|
| **v0** | `v0` | ✅ shipped | — |
| **v2-prep** | `v2-prep` | ✅ shipped | — |
| **v1** | `v1.0` | ✅ shipped | — |
| **v2** | — | 🟡 ready to tag | all features implemented; needs integration test pass |
| **v3** | — | 🔵 planned | v2 must ship first |
| **v4** | — | 🔵 planned | v3 must ship first |

**v2 done as of 2026-06-16:** All remaining v2 features implemented:
- Test-asset cleanup: zero committed binaries in `test-assets/`; download script generates all fixtures
- tui-monitor.py retired: removed from upscale-video.sh TTY path, file deleted
- Throttle warning in TUI: `⚠ THROTTLING` flag when SM clock drops ≥15% at temp ≥85°C
- `xhigh` preset for video: Real-ESRGAN 4× + system h264_nvenc re-encode (`-NVENC=1`)
- `--dedup` / `-D`: mpdecimate frame dedup before inference; framerate restored after
- `--interpolate 2x` / `-I 2x`: RIFE 2× (or ffmpeg minterpolate fallback)
- `--thermal-mode` / `-T`: conservative|balanced|performance sleep between phases
- TensorRT backend stub: validates deps, falls back to realesrgan with install guidance
- `tool upscale image|video|audio`: unified command grammar front-end
- Per-job audit manifest: `OUTPUT.audit.json` with input/output SHA256, model, timings
- Content-based model auto-select: `-m auto` uses ImageMagick saturation+edge heuristic

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
| `xhigh` | 4× | RealESRGAN_x4plus | yes | 0 (auto) | Max quality; targets 4K output from HD source |

**Video presets** (extends existing `low/medium/high`, adds `xhigh`):

| Preset | Engine | Scale | Encode | Notes |
|---|---|---|---|---|
| `low` | ffmpeg lanczos | 2× | libx264 | CPU only; seconds per clip |
| `medium` | RealCUGAN | 2× | libx264 | Default; AI-enhanced |
| `high` | Real-ESRGAN | 4× | libx264 | Best quality |
| `xhigh` | Real-ESRGAN | 4× | NVENC (blocked until NVENC fix below) | Max quality; targets 4K output |

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

- **Test-asset cleanup: zero committed binaries** ✓ done — removed all 14.7 MB from `test-assets/`; download script generates all fixtures (synthetic benchmark images + ffmpeg-generated test-clip.mp4).
- **TensorRT / PyTorch FP16 backend with frame batching** ✓ stub done — `-e tensorrt` validates PyTorch+CUDA deps, falls back to realesrgan with install guidance. Full FP16 inference path deferred to v3.
- **NVENC encode** ✓ done — `xhigh` preset uses system h264_nvenc (lossless intermediate → nvenc re-encode); `-NVENC=1` flag wired internally. Confirmed system ffmpeg has h264/hevc/av1_nvenc.
- **Duplicate-frame skip** ✓ done — `-D` flag: mpdecimate pre-filter, framerate restored post-upscale.
- **RIFE frame interpolation** ✓ done — `-I 2x` flag: uses RIFE binary if available, falls back to ffmpeg minterpolate.
- **`--thermal-mode conservative|balanced|performance`** ✓ done — `-T` flag: conservative inserts 5 s sleep between phases; balanced/performance are no-ops.
- **Content-based model auto-select** ✓ done — `-m auto` uses ImageMagick saturation+edge density → selects RealESRGAN_x4plus_anime_6B or RealESRGAN_x4plus.
- **Unified command grammar** ✓ done — `tool upscale image|video|audio FLAGS INPUT OUTPUT`.
- **Per-job audit manifest** ✓ done — `OUTPUT.audit.json` / `OUTPUT.video.audit.json`: input/output SHA256, model, scale, tile, precision, elapsed seconds, integrity status.

### v2 prep tasks (can land in v1.x)

These are prerequisites for the unified TUI but are small enough to ship early:

1. Add `-q low|medium|high|xhigh` to `upscale-image.sh`. ✓ done
2. Build Python Textual TUI app (`tool tui` entry point). ✓ done — `scripts/tui.py`, entry point `tool tui`.
3. Implement sidecar JSON writer in `upscale-image.sh` and `upscale-video.sh`; implement detach/reattach in TUI. ✓ done — see "TUI: status" below.

### TUI: status

The TUI (`scripts/tui.py`, `tool tui`) is feature-complete for v2. Everything the spec calls for is implemented and unit-tested (`scripts/test_tui.py`, run by `test.sh` section 30b):

- **Core interactive layer** ✓ — layout, scanning, default selection (images all-on; first-unprocessed video only), per-section select/unselect buttons, aggregate ETA bar, all keyboard shortcuts, job execution, GPU polling, log pane.
- **File-browser view + scoped selection** ✓ — subdirectories render as `📁` folder headers with indented files; `[a]`/`[n]` are scoped to the cursor's section **and** subdirectory (not global). `[R]` reset wipes every item's output (file + sidecars) and re-queues for a clean re-run.
- **Open output on completion** ✓ — when a batch finishes, the output folder(s) that received files pop open in the OS file manager (`xdg-open` with file-manager fallbacks on Linux, `open` on macOS); best-effort, no-ops headlessly.
- **Sidecar writers** ✓ — `upscale-image.sh` (`{stem}.{fmt}.progress.json`) and `upscale-video.sh` (`{output}.progress.json`) write `running`/`done`/`failed` with live `pct`; video adds `fps`/`remaining`.
- **Reattach / session persistence** ✓ — `_reattach_sidecars()` on mount marks live jobs `▶ active`; `_tick_sidecars()` polls every 5 s for detached jobs. Field normalization (`fps` → `throughput`) is centralized in `normalize_sidecar()`.
- **Adaptive ETA refinement** ✓ — `_after_job` records actual rate and re-seeds remaining same-type queued items to the running average.
- **Preset + input-dir interactivity** ✓ — `[P]` cycles preset (re-seeds ETA), `[d]` opens a `DirPrompt` modal to rescan a new root.
- **Section counts during active job** ✓ — `_refresh_active_panel()` calls `_update_section_counts()`.
- **`tui-monitor.py` retired** ✓ — deleted; `grep -r 'tui-monitor' scripts/` returns nothing.

**Remaining: live validation only (needs GPU).** The progress regexes are unit-tested against captured sample lines but not yet confirmed against live inference output:

- `parse_image_progress()` targets Real-ESRGAN's `Testing N name` / `Tile K/M` stdout — tile-counter format may vary between versions.
- `parse_video_progress()` targets video2x's `frame=N/M … fps=X … remaining=HH:MM:SS`. The TUI runs the video script non-interactively (no TTY), so confirm the raw stdout format once live.
- Run the manual TUI test plan (sections 31–48 in `test.sh`) before tagging v2.

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

> **Multi-platform port (in progress, 2026-06-25):** see [omarchy-port.md](omarchy-port.md) — change log for the Mac/Ubuntu/WSL2/Omarchy targets plus the **open question** of which image-inference/dependency stack is objectively best (the PyTorch+basicsr path is the main portability blocker). Must be resolved before locking the v3 stack.

### Supported operating systems — test status

What has actually been run, not what is assumed to work. Only Omarchy has been exercised end-to-end; everything else is **untested** until someone runs `./scripts/setup.sh && ./scripts/test.sh` on that target and records the result here.

| OS / target | setup.sh | test.sh (fast) | GPU inference | TUI (manual) | Status |
|---|---|---|---|---|---|
| **Omarchy (Arch)** | ✅ | ✅ green | ✅ RealCUGAN 2× verified | 🟡 live video-progress check pending | 🟡 in progress — primary dev box |
| **Ubuntu 24.04** | ❓ | ❓ | ❓ | ❓ | ⬜ untested |
| **WSL2 (Ubuntu 24.04)** | ❓ | ❓ | ❓ | ❓ | ⬜ untested |
| **macOS** | ❓ | ❓ | ❓ | ❓ | ⬜ untested — known blockers: video2x AppImage is Linux-only (needs brew/source NCNN front-end); torch cu118 wheels N/A on Apple Silicon |

Legend: ✅ verified · 🟡 in progress · ⬜ untested · ❓ unknown (not yet run). Update a row only after running the suite on that OS — do not promote to ✅ on assumption.

## v2.x — bug bashing, stabilization & quality tuning (next phase)

Lock v2 down before the v3 Rust rewrite. Focus is correctness, robustness, and
output-quality tuning on the existing Python pipeline — no new feature surface.

- **Bug bashing.** Exercise the full TUI surface against real inputs (reset, per-section / per-subdirectory select, force-redo, retry, pause/cancel/resume, dir change, options modal); hunt and fix edge-case crashes, stale-state bugs, and progress/ETA glitches. Convert each fix into a regression test in `scripts/test_tui.py`.
- **Stabilization.** Confirm the live progress regexes against real GPU stdout (`parse_image_progress` / `parse_video_progress`, the open item above); harden sidecar reattach and zombie-job reconciliation; complete the manual TUI test plan (`test.sh` sections 31–48) and the per-OS matrix above.
- **Video & image optimization.** Tune throughput and output quality: tile-size / VRAM heuristics, dedup + interpolation interaction, NVENC vs libx264 quality/size tradeoffs, thermal pacing on the 3050 Mobile reference box.
- **Parameter testing.** Systematically sweep `-q` presets and raw overrides (scale, model, tile, face, engine) across the demo asset set; record quality/time results and fold the best defaults back into the preset tables above.
- **Legal audit (`/legal`).** ✓ done (2026-06-28) — MIT `LICENSE` added (AS-IS / no-warranty / no-liability); `THIRD_PARTY_NOTICES` inventories every dependency, engine, and model weight with source + SPDX license; README "License & third-party notices" section adds the operational-risk note and points to both. **Key finding:** the repo redistributes nothing — `tools/`, `*.pth`, and venvs are all gitignored and fetched by `setup.sh`, so the GPL-3.0 copyleft of video2x and this ffmpeg build attaches to the user's local install, not to the project source. Outbound license is therefore unconstrained; users inherit the GPL obligations knowingly via the docs. Feeds the `/ship` legal stage below.

- **Quality-measurement harness (`scripts/quality-metrics.py`).** ✓ built (2026-06-28) — full-reference PSNR + SSIM (LPIPS optional, needs `lpips`) between an upscaled output and its GT, `--json` for machine use, `--min-psnr`/`--min-ssim` to gate, exit-code contract (0 measured/met · 1 below threshold · 2 IO/usage). Mismatched sizes (non-integer scale) are Lanczos-resized to GT and flagged informational. Wired into `test.sh` via `assert_quality`, scoped to the two tiny Set5 benchmark images (butterfly 2×, baby 4×) so the gate stays inside the 4 GB / RTX 3050 Mobile budget — **per the hardware constraint, quality validation runs ≤5 images + one short clip, never the full 14-asset sweep on the local box.**
- **Per-tier absolute quality thresholds.** ✓ mechanism (2026-06-28) — the metric is absolute (hardware-independent) but the *pass bar* is per-tier/per-task: each invocation supplies the minimum PSNR/SSIM appropriate to the tier that ran, so a low-end box on a low tier passes against the low bar and is not failed for not matching a high tier. Enforced bars start conservative (catch a broken pipeline: blank/noise/wrong output) and tighten toward the `docs/test-plan.md` literature targets (butterfly ≥28, baby ≥32) once a real GPU run records the **calibration baseline**. Real-ESRGAN is a GAN (trades PSNR for perceptual sharpness), so literature targets are shown, not yet the gate.

  **Calibration baseline — measured on RTX 3050 Mobile (4 GB), 2026-06-28** (`test.sh --integration-images`, real Real-ESRGAN inference):

  | Asset | Tier | Measured PSNR | Measured SSIM | Enforced bar | Literature target |
  |---|---|---|---|---|---|
  | butterfly | low / 2× | **24.731 dB** | **0.8714** | ≥24 / ≥0.70 ✅ | ≥28 dB |
  | baby | medium / 4× | **24.410 dB** | **0.7347** | ≥24 / ≥0.60 ✅ | ≥32 dB |

  **Finding:** measured PSNR (24.7 / 24.4) sits **well below** the literature targets (28 / 32) while clearly clearing the conservative bars. This is the GAN-vs-PSNR tradeoff confirmed on real hardware, not a pipeline defect — Real-ESRGAN sacrifices pixel fidelity for perceptual sharpness, so PSNR systematically under-rates it. **Consequence:** do **not** promote the enforced bars to the literature PSNR targets; add **LPIPS** (the fair perceptual metric) and calibrate any tightening against that instead. Bars left unchanged pending that work.
- **Hardware-adaptive quality gradient (`-q auto`).** ✓ images (2026-06-28) — `upscale-image.sh -q auto` probes free VRAM (the binding constraint) and slides the tier: `<4 GiB → low (2×, tile 256)`, `4–8 → medium (4×, tile 512)`, `8–12 → high (4×+face)`, `≥12 → xhigh (4×+face, tile 0)`. Breakpoints mirror the existing VRAM→tile map for consistency. Verified on this box: 3564 MiB free → `low`.

#### Quality-gate work queue (active — being worked through now)

Concrete, ordered follow-ups that finish the quality-gate epic. Status: ☐ not started · ◧ in progress · ☑ done.

1. **☑ `-q auto` for `upscale-video.sh`** (2026-06-28). Mirrors the image gradient onto the video preset ladder, with the two video-specific constraints the image path doesn't have:
   - No usable GPU (`nvidia-smi` fails) → degrades to the CPU **`low`** (ffmpeg-lanczos) preset — the only no-GPU video path. Headline difference from the image script (which hard-requires a GPU); the probe is failure-tolerant (`|| true`) so `pipefail`+`set -e` don't abort before degrading.
   - VRAM slide: `<1 GiB → low`, `1–4 → fast` (realesr-animevideov3 compact, lightest AI), `4–8 → medium` (RealCUGAN 2×), `8–12 → high` (Real-ESRGAN 4×), `≥12 → xhigh` (Real-ESRGAN 4× + NVENC).
   - **RAM headroom:** dedup/chunk/NVENC stage large lossless temp files; under ~2 GiB free `MemAvailable`, holds the tier one AI notch lower. Resolved before validation so batch recursion re-passes a fixed tier (no per-file re-probe). Verified on this box (3564 MiB → `fast`), all five VRAM bands, and the stubbed no-GPU → `low` path.
2. **☐ Multi-resource tier refinement.** Fold `gpu_count` into the tier where it actually binds. **Note from item 1:** RAM only binds the *video* path (temp-file staging) — for single-image inference VRAM is the sole binding constraint, so `upscale-image.sh -q auto` stays VRAM-driven by design rather than carrying a guard that never fires. `gpu_count`-aware tiering is deferred until the inference path is actually multi-GPU-aware (today it targets device 0 only), otherwise a higher tier would over-promise.
3. **◧ Calibrate per-tier thresholds against a real GPU baseline.** **Baseline recorded 2026-06-28** (RTX 3050 Mobile, real Real-ESRGAN inference — see the table under "Per-tier absolute quality thresholds" above): butterfly 24.731 dB / 0.8714, baby 24.410 dB / 0.7347. **Outcome:** measured PSNR lands far below the literature targets purely from the GAN tradeoff, so promoting the bars to those PSNR targets would wrongly fail good output. **Remaining:** add LPIPS and re-calibrate any threshold tightening against the perceptual metric, not PSNR. Enforced bars stay conservative until then.
4. **☐ Wire `assert_quality` for the video path.** Extend the harness with a short-clip frame-extract → `quality-metrics.py` comparison so the video gate matches the image gate (still inside the 4 GB / one-short-clip budget).

**Exit gate.** v2 closes by passing the **`/ship`** release-readiness filter end-to-end (functional · quality · security · docs · governance · **legal** · release). The `/legal` stage is blocking: ship an **AS-IS, no-warranty, no-liability** disclaimer and confirm every dependency **and bundled AI model weight** (Real-ESRGAN, GFPGAN, video2x, …) is license-compatible for redistribution, with a complete `THIRD_PARTY_NOTICES`. No public release until `/ship` returns GO.

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

## Open research question: model quality gap vs. Topaz

**Question:** Does this project reach Topaz Video AI / Topaz Photo AI output quality by v3–v4, given equivalent hardware?

**Current assessment (2026-06-11):** Pipeline parity is achievable — TensorRT (v2) + Rust zero-copy pipeline (v3) close the throughput gap. The remaining variable is model weights, not architecture.

**Why the gap may already be closed:** Perplexity research confirms open-source model quality is near-feature-parity with Topaz for common cases. Candidate models to evaluate:

- `realesr-animevideov3` / `RealESRGAN_x4plus` — current defaults; strong on clean sources
- `ESRGAN` successors (HAT, SwinIR, DAT) — transformer-based, outperform ESRGAN on benchmarks (PSNR/SSIM) for photographic content
- `RealHAT`, `RealDAT` — Real-world degradation variants of the above; closer to Topaz's training regime
- `BSRGAN` / `LDL` — specifically trained on heavily compressed / mixed-degradation inputs (archival footage use case)
- `Restormer` — state-of-art for image restoration (denoising, deblur) as a pre-pass before upscaling

**Known gap cases** (where Topaz still leads as of 2026):
- Heavily compressed archival footage (VHS, DVD rips with blocking + noise)
- Fine text rendering at high scale factors
- Synthetic/CG content with sharp edges (aliasing artifacts)

**Action item (v2 or post-v2):** Add a `-m auto` model-selection mode that runs a content classifier (anime vs. photographic vs. archival/compressed) and routes to the best available open model. Candidate classifiers: CLIP zero-shot, or a lightweight CNN trained on the task. This is the single highest-leverage remaining item for closing the quality gap without proprietary training data.

**Research references to check:** `chainner`/`openmodeldb.info` community model releases; NTIRE and AIM workshop proceedings (annual CVPR/ECCV); `xinntao/Real-ESRGAN` issues tracker for model comparisons.

---

## Hardware: squeeze vs buy

Software first — v1+v2 levers stack to roughly **5–10×** on owned hardware before any purchase. Buy only when the job class changes:

| Trigger | Buy | Why |
|---|---|---|
| Routine `high`/4× archival on hour-long files | used RTX 3090 (24 GB) | VRAM is the binding constraint (the `--tile 512` rule exists because of 4 GB), ~3–5× throughput, no tiling |
| Several files/day, SD→HD | RTX 4070 Super (12 GB) | ~2.5–3×, current-gen efficiency |
| 1080p→4K hour-long content | 16–24 GB class | 5× input pixels of the reference job; even squeezed 3050 is back to ~30+ h |

Caveats: estimator's geometric-mean model flatters high-bandwidth cards (5090 "28×" is theoretical; NCNN path can't use its Tensor cores either); 3050 Mobile is a laptop part — a desktop card implies a new machine, not an upgrade.
