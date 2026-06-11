# TUI Wireframe — media-restore v2

Built with [Textual](https://github.com/Textualize/textual). Single entry point: `tool tui`.

---

## Default selection rules (startup)

| Media | Default | Rationale |
|---|---|---|
| Images | **All unupscaled** selected (`[✓]`); already-upscaled shown `✓ done` but skipped | Images are fast; batch-all is safe |
| Video | **One video** selected (`[✓]`); rest start unchecked (`[ ]`) | Videos are long — default prevents accidentally queueing hours of work |
| Audio | **All unupscaled** selected (`[✓]`); already-upscaled shown `✓ done` but skipped | Same rationale as images |

"Already upscaled" = matching file found in `output/` at startup (detected by output path, not a separate state file).

---

## Persistent aggregate ETA

The bottom status bar is **always visible** and always shows the total estimated time for all currently-selected, not-yet-done items. It updates immediately whenever the user checks or unchecks any item.

```
Total ETA  ≈ 28 m   (3 img × ~2 m  +  1 vid × ~22 m  +  2 aud × ~1 m)
```

During a run the bar also shows time elapsed and time remaining for the whole batch:

```
Elapsed  6 m  ·  Total ETA  ≈ 22 m remaining   (9 items left)
```

Each item's estimate comes from `perf-estimate.py` hardware profile (instant, ±50 %). Once a job starts, its measured throughput refines its own per-item estimate and the aggregate updates accordingly.

---

## Layout — running state

Two-column split. Left: scrollable file checklist (all media types, sectioned). Right: stacked panels for the active job, GPU stats, and log. Two persistent rows at the bottom: status/ETA bar and key bindings bar.

```
╔═ media-restore v2 ═══════════════════════════════════════════════════════════════════════════════════════════╗
║  Preset [medium ▼]   Input [input/ ▶]                                                                        ║
╠══ Files ══════════════════════════════════════════════════════╦══ Active Job ══════════════════════════════╣
║  ── Images  9 done · 1 active · 2 queued · 1 failed           ║  great-wave.jpg                           ║
║     [ select all ]  [ unselect all ]                          ║  ────────────────────────────────────────  ║
║  [✓] butterfly.jpg            ✓ done     2026-06-10 14:02     ║  ████████████████░░░░░░░░  67%             ║
║  [✓] baby.png                 ✓ done     2026-06-10 14:03     ║  ████████████████░░░░░░░░  67%             ║
║  [✓] douglas-portrait.jpg     ✓ done     2026-06-10 14:05     ║  1 m 12 s remaining                       ║
║  [✓] great-wave.jpg           ▶ active   67%  1 m 12 s left   ║  3.2 tiles/s · tile 8 / 12                ║
║  [✓] metro-landscape.jpg      · queued                        ╠══ GPU ════════════════════════════════════╣
║  [✓] yosemite-valley.jpg      · queued                        ║  Util   ██████████░░░░  82 %              ║
║  [✓] bsd_45096.png            ✓ done     2026-06-10 13:58     ║  VRAM   ████████████░░  3.1 / 4.0 GB      ║
║  [✓] flower-foliage.jpg       ✓ done     2026-06-10 14:00     ║  Temp   71 °C  ·  Clock  1420 MHz         ║
║  [✓] nyc-night.jpg            ✓ done     2026-06-10 14:01     ╠══ Log ════════════════════════════════════╣
║  [ ] 76-ball-sign.jpg         ○ excluded                      ║  14:05:32  tile 8/12 complete             ║
║  [✗] flower-foliage-q20.jpg   ✗ failed   OOM at tile 3/12     ║  14:05:30  tile 7/12 complete             ║
║  ── Video  1 selected · 1 excluded                            ║  14:05:28  start great-wave.jpg           ║
║     [ select all ]  [ unselect all ]                          ║  14:05:10  ✓ nyc-night.jpg done           ║
║  [✓] test-clip.mp4            · queued                        ║  14:05:05  ✓ flower-foliage.jpg done      ║
║  [ ] sf-market-1906.mp4       ○ excluded                      ║                                           ║
║  ── Audio  2 queued                                           ║                                           ║
║     [ select all ]  [ unselect all ]                          ║                                           ║
║  [✓] interview.wav            · queued                        ║                                           ║
║  [✓] narration.mp3            · queued                        ║                                           ║
╠═══════════════════════════════════════════════════════════════╩═══════════════════════════════════════════╣
║  Elapsed  6 m  ·  Total ETA  ≈ 26 m remaining   (1 active · 4 queued · 1 failed · 2 excluded)            ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║  [↑↓] navigate   [SPACE] toggle   [a] all   [n] none   [t] invert   [r] retry failed   [f] force redo     ║
║  [s] start   [p] pause/resume   [c] cancel job   [d] change dir   [q] quit                                ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## Layout — pre-run state (first open)

Full two-column layout from the moment the TUI opens — no layout shift when a job starts. The right panels (Active Job, GPU, Log) are visible immediately in idle state. Same two-row persistent footer: status/ETA on top, key bindings below.

```
╔═ media-restore v2 ═══════════════════════════════════════════════════════════════════════════════════════════╗
║  Preset [medium ▼]   Input [input/ ▶]                                                                        ║
╠══ Files ══════════════════════════════════════════════════════╦══ Active Job ══════════════════════════════╣
║  ── Images  3 done · 4 queued                                 ║  No active job                            ║
║     [ select all ]  [ unselect all ]                          ║  ────────────────────────────────────────  ║
║  [✓] butterfly.jpg            ✓ done     2026-06-09 11:14     ║  Press [s] to start                       ║
║  [✓] baby.png                 ✓ done     2026-06-09 11:15     ║                                           ║
║  [✓] bsd_45096.png            ✓ done     2026-06-09 11:18     ╠══ GPU ════════════════════════════════════╣
║  [✓] great-wave.jpg           · queued   est. ~2 m            ║  Util   ░░░░░░░░░░░░░░   0 %             ║
║  [✓] metro-landscape.jpg      · queued   est. ~2 m            ║  VRAM   ██░░░░░░░░░░░░   0.6 / 4.0 GB   ║
║  [✓] portrait-conv.jpg        · queued   est. ~2 m            ║  Temp   52 °C  ·  Clock  300 MHz         ║
║  [✓] yosemite-valley.jpg      · queued   est. ~3 m            ╠══ Log ════════════════════════════════════╣
║  ── Video  1 selected · 2 excluded                            ║  [dim]waiting for job…[/dim]              ║
║     [ select all ]  [ unselect all ]                          ║                                           ║
║  [✓] test-clip.mp4            · queued   est. ~22 m           ║                                           ║
║  [ ] sf-market-1906.mp4       ○ excluded                      ║                                           ║
║  [ ] france-1947.mp4          ○ excluded                      ║                                           ║
║  ── Audio  2 queued                                           ║                                           ║
║     [ select all ]  [ unselect all ]                          ║                                           ║
║  [✓] interview.wav            · queued   est. ~1 m            ║                                           ║
║  [✓] narration.mp3            · queued   est. ~1 m            ║                                           ║
╠═══════════════════════════════════════════════════════════════╩═══════════════════════════════════════════╣
║  Total ETA  ≈ 31 m   (4 img × ~2 m  +  1 vid × ~22 m  +  2 aud × ~1 m)                                   ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║  [↑↓] navigate   [SPACE] toggle   [a] all   [n] none   [t] invert   [r] retry failed   [f] force redo      ║
║  [s] start   [p] pause/resume   [c] cancel job   [d] change dir   [q] quit                                  ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

Selecting the second video with `SPACE` immediately updates the ETA row (layout and key bar unchanged):

```
║  Total ETA  ≈ 53 m   (4 img × ~2 m  +  2 vid × ~22 m  +  2 aud × ~1 m)                                   ║
```

---

## Item states

Each row has two independent fields: a **checkbox** (selected/excluded) and a **status**.

| Checkbox | Status | Meaning |
|---|---|---|
| `[✓]` | `✓ done  <timestamp>` | Output exists; tracked; will **not** re-run unless `[f]orce` |
| `[✓]` | `▶ active  <pct>  <eta>` | Currently processing |
| `[✓]` | `· queued  est. ~<n> m` | Waiting in queue; per-item hardware-profile estimate shown |
| `[✓]` | `✗ failed  <reason>` | Last run errored — `[r]` retries all failed |
| `[ ]` | `○ excluded` | Unchecked by user; skipped entirely |

Done items remain `[✓]` in the list so their completion is visible, but they are **excluded from the queue and the ETA total**.

---

## Aggregate ETA mechanics

```
Total ETA = Σ est(item)  for all items where checkbox=[✓] and status=queued
```

- Each item's `est(item)` comes from `perf-estimate.py` hardware profile (instant, ±50 %).
- Once a job finishes, its actual duration replaces the estimate for any remaining items of the same type and preset in the same session (running average, improves accuracy for later items).
- The total recomputes immediately on every checkbox toggle — user sees the impact of adding/removing items before starting.
- During a run the bar switches to `Elapsed X m · Remaining ≈ Y m` derived from measured throughput on the active job plus profile estimates for queued items.

---

## Active Job panel (per-media throughput)

| Media | Throughput metric | Progress basis |
|---|---|---|
| Image | `tiles/s` (single large file) or `files/s` (batch of small files) | tiles or files done / total |
| Video | `fps` | frames done / total frames |
| Audio | `s audio / s elapsed` | seconds of audio processed / total duration |

---

## Keyboard shortcuts

All shortcuts are **permanently displayed** in the two-row key bindings bar at the bottom of the screen (implemented via Textual `BINDINGS` + `Footer`). Users never need to look up docs to find a key.

| Key | Action | Bar row |
|---|---|---|
| `↑ / ↓` | Navigate file list | row 1 |
| `SPACE` | Toggle checkbox; ETA updates immediately | row 1 |
| `a` | Select all unfinished items | row 1 |
| `n` | Deselect all | row 1 |
| `t` | Invert selection | row 1 |
| `r` | Retry all `✗ failed` items | row 1 |
| `f` | Force re-run focused `✓ done` item | row 1 |
| `s` | Start batch | row 2 |
| `p` | Pause / resume active job | row 2 |
| `c` | Cancel active job | row 2 |
| `d` | Change input directory | row 2 |
| `q` | Quit (prompts if jobs are active) | row 2 |

Row 1 = selection/navigation controls. Row 2 = job control + app commands. The split keeps related actions grouped visually.

---

## Startup behaviour

1. Scan `input/images/`, `input/video/`, `input/audio/` (or `--input` path).
2. Scan matching paths under `output/` — items with existing output → status `✓ done`, file mtime as timestamp, excluded from ETA total.
3. Apply per-media default selection:
   - Images: `[✓]` all items where no output exists.
   - Video: `[✓]` first item (alphabetical) where no output exists; all others start `[ ]`.
   - Audio: `[✓]` all items where no output exists.
4. Compute aggregate ETA from hardware profile for all `[✓]`-checked, not-done items; display immediately in bottom bar.
5. If a `.progress.json` sidecar exists for any file → mark it `▶ active` and reattach to its ETA stream.

---

## Session persistence

Done items are tracked purely by output file existence — re-launching the TUI re-scans `output/` and reconstructs state. No separate state file is needed for completion tracking. In-progress jobs write a `.progress.json` sidecar that survives TUI close; relaunching reattaches automatically (step 5 above).

---

## Textual widget mapping

| Panel | Textual widget |
|---|---|
| File checklist | Custom `ChecklistView(ScrollableContainer)` with `ChecklistItem` rows |
| Section headers | `Label` + two `Button` widgets (`[ select all ]` / `[ unselect all ]`) in a `Horizontal`; scoped to that media type only |
| Active Job progress bar | `ProgressBar` + `Label` in a `Vertical` container |
| GPU stats | `Static` updated via `set_interval(2, poll_gpu)` (port from `tui-monitor.py`) |
| Log pane | `RichLog` (auto-scrolling, capped at 200 lines) |
| Preset / input selectors | `Select` widgets in app `Header` |
| ETA status bar (persistent) | Custom `StatusBar(Static)` reactive to checklist state; sits above `Footer`, always rendered |
| Key bindings bar (persistent, 2 rows) | Textual `Footer` with `BINDINGS` declared on the App; row 1 = selection/nav, row 2 = job/app; always visible, zero user discovery cost |
