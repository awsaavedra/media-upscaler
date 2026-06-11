# Roadmap — version tags

Derived from [market-gap.md](market-gap.md) (2026-06-09). Focus order: 1. usability, 2. efficient image/video processing; TUI/feedback/setup fold into usability.

**Status (2026-06-09): v0 verified stable (32/32 integration tests, GPU path confirmed) and tagged; v1 cleared to start.** Open risk: v1 ≤ 10 h exit bar pending the 854×480 fast-preset benchmark (first v1 task).

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

- **Batch folder input — zero per-file invocation** — drop a folder (or loose files) into `input/images/` / `input/video/` and run one command (no args = sweep both): recursive discovery by extension, idempotent output naming mirroring the input tree, skip already-converted outputs, continue-on-error with end-of-run summary. Composes with chunked resume: an interrupted sweep restarts where it left off. Acceptance: drop a nested folder of mixed media into `input/video/`, one command converts everything, a second run is a no-op, one corrupt file doesn't abort the set.
- **Chunked processing + `--resume`** — ffmpeg-segment into ~5 min chunks, upscale per chunk, concat; per-chunk state in sidecar JSON. Market-gap: single most impactful feature for jobs > 10 min. Acceptance: kill mid-job, resume, lose ≤ 1 chunk; output bit-identical duration vs single-pass.
- **Progress sidecar JSON + TUI re-attach** — writer updates `{output}.progress.json` (chunk, frame, fps, ETA) every few seconds; `tui-monitor.py --attach` tails it. Acceptance: SSH drop, reconnect, live state visible.
- **Calibration probe → trustworthy ETA** — upscale ~30 real source frames before committing, print measured fps, ETA, temp-disk and VRAM forecast; abort prompt if disk short. Replaces spec-ratio projection for the pre-job estimate. video2x `-b` (benchmark: discard frames, report avg fps) is the ready-made primitive. Acceptance: ETA within ±20 % of actual on test clips.
- **Post-mux integrity check** — duration drift ≤ 100 ms, frame count match, A/V sync ≤ 40 ms; fail loudly with actionable message (guards Video2X's documented 2-frame-loss / audio-drift bugs).
- **Temp-disk preflight** — estimate chunk + temp size, verify free space on output filesystem before start.
- **Throttle warning in TUI** — flag sustained SM-clock drop at temp ≥ threshold (data already polled).

### Efficiency (image/video processing)

- **`-q fast` preset: compact video model** — `realesr-animevideov3` (SRVGGNet compact). Verified 2026-06-09: supported by the installed Video2X (its default model, native 2×/3×/4×); benchmark on test clip ran ≥ 9.5 fps vs 2.83 fps medium → ≥ 3.4× (lower bound, encode excluded). First v1 task: benchmark at 854×480 to validate the ≤ 10 h exit bar — pixel-scaled projection lands ~1.4–1.6 fps (~16 h); if < 2.5 fps measured, pull the TensorRT backend forward from v2 or revise the bar. Acceptance: ≥ 2 fps @ 854×480 on 3050 Mobile + documented quality spot-check vs `medium`.
- **VRAM probe → auto tile + FP16 defaults** — map free VRAM to tile size (200/4 GB, 300/6 GB, 400/8 GB, 600/12 GB), FP16 on where supported. Acceptance: no OOM at defaults on 4 GB; no manual `--tile` needed for common inputs.

## v2.0 — differentiation

Exit criteria: reference job **≤ 4 h** on 3050 Mobile; feature set matches the "Your Target" column of the market-gap feature matrix.

- **Python Textual TUI** — replace `scripts/tui-monitor.py` (Rich) with a full [Textual](https://github.com/Textualize/textual) app: job queue panel, per-job progress bars, live GPU stats (temp/VRAM/clock/throttle flag), log pane, keyboard shortcuts to pause/cancel/reattach. **Every CLI flag and argument permutation must be reachable from the TUI** — no flag available on the command line that is absent or non-configurable in the TUI. Single entry point: `tool tui`. Acceptance: all v1 TUI data visible; every CLI option exposed; attach/detach via sidecar JSON; no Rich import remaining in TUI path.
- **TensorRT / PyTorch FP16 backend with frame batching** — use Tensor cores instead of NCNN shader FP16; expected 2–4× on RTX 30-series. Larger lift; keep NCNN as fallback. Candidate for promotion to v1 if `-q fast` misses the exit bar (see v1).
- **NVENC encode** — blocked inside Video2X: bundled AppImage libav fails with error -22 on `h264_nvenc` (verified 2026-06-09, with and without `--pix-fmt yuv420p`). System ffmpeg has h264/hevc/av1_nvenc, so the path is newer AppImage, or lossless intermediate + system-ffmpeg encode. Minor lever (~1.2×), hence v2.
- **Duplicate-frame skip** — mpdecimate-style dedup before inference, reuse upscaled frame via mapping; 1.2–2× on low-motion content.
- **RIFE frame interpolation** — `--interpolate 2x`.
- **Audio SR** — AudioSR wrapper: standalone subcommand + opt-in `--enhance-audio` for video (only 3-modality OSS CLI; see [local-upscaling-audio.md](local-upscaling-audio.md)).
- **`--thermal-mode conservative|balanced|performance`** — act on throttle data, not just warn.
- **Content-based model auto-select** — anime vs photographic vs text-heavy detection → model recommendation.
- **Unified command grammar** — `tool upscale image|video|audio --input … --output …` front-end over existing scripts.
- **Per-job audit manifest** — input/output hashes, model, tile, precision, per-stage timings, warnings. (Batch folder input itself is v1; this adds the audit trail + glob patterns outside `input/`.)

## v3.0 — Rust rewrite (primary goal: speed)

Exit criteria: reference job measurably faster than v2 on identical hardware; full feature parity; all integration tests pass against the Rust binary; Python scripts retired.

Primary motivation is throughput — Rust eliminates Python interpreter overhead, enables zero-copy buffer passing to inference engines, and opens direct CUDA/Vulkan interop without subprocess boundaries. The Python codebase is the reference implementation for behavior; v3 is a port, not a redesign — no new features until parity is confirmed.

- **ratatui TUI** — replace Textual with [ratatui](https://github.com/ratatui-org/ratatui): same panels (job queue, progress, GPU stats, log), same sidecar-JSON attach protocol, same keyboard shortcuts. **Every CLI flag and argument permutation must be reachable from the TUI** — parity with the v2 Textual TUI is the minimum bar; any flag added to the CLI must have a corresponding TUI control. Single binary entry point. Acceptance: feature-for-feature parity with the Textual TUI including full CLI surface; no Python runtime dependency.
- **Core pipeline in Rust** — port chunked processing, resume logic, batch folder sweep, progress sidecar writer, preflight checks (disk, VRAM probe), integrity checker, and perf estimator to Rust. FFI or subprocess calls to NCNN/TensorRT stay; no rewrite of inference engines.
- **CLI parity** — same flags and exit codes as v2 Python CLI; shell scripts that consumed v2 output work unchanged.
- **Test suite port** — `scripts/test.sh` integration tests rewritten to invoke the Rust binary; same acceptance criteria.
- **Dependency audit** — `Cargo.lock` committed; no yanked crates; `cargo audit` clean at ship.

## Hardware: squeeze vs buy

Software first — v1+v2 levers stack to roughly **5–10×** on owned hardware before any purchase. Buy only when the job class changes:

| Trigger | Buy | Why |
|---|---|---|
| Routine `high`/4× archival on hour-long files | used RTX 3090 (24 GB) | VRAM is the binding constraint (the `--tile 512` rule exists because of 4 GB), ~3–5× throughput, no tiling |
| Several files/day, SD→HD | RTX 4070 Super (12 GB) | ~2.5–3×, current-gen efficiency |
| 1080p→4K hour-long content | 16–24 GB class | 5× input pixels of the reference job; even squeezed 3050 is back to ~30+ h |

Caveats: estimator's geometric-mean model flatters high-bandwidth cards (5090 "28×" is theoretical; NCNN path can't use its Tensor cores either); 3050 Mobile is a laptop part — a desktop card implies a new machine, not an upgrade.
