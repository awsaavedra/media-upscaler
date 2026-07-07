# TUI & preset reference — media-upscaler

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
╔═ media-upscaler ═════════════════════════════════════════════════════════════════════════════════════════════╗
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
║  [s] start   [p] pause/resume   [c] cancel job   [P] preset   [o] options   [d] change dir   [q] quit     ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## Layout — pre-run state (first open)

Full two-column layout from the moment the TUI opens — no layout shift when a job starts. The right panels (Active Job, GPU, Log) are visible immediately in idle state. Same two-row persistent footer: status/ETA on top, key bindings below.

```
╔═ media-upscaler ═════════════════════════════════════════════════════════════════════════════════════════════╗
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
║  [s] start   [p] pause/resume   [c] cancel job   [P] preset   [o] options   [d] change dir   [q] quit       ║
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

## Subdirectory grouping (file-browser view)

Inputs are scanned recursively, so a media section is not necessarily flat. When a
source subdirectory exists under `input/<type>/`, the TUI renders it like a file
browser: a **folder header** (`📁 <name>/`) names the subdirectory, and the files
that live in it are listed **indented** beneath it. Files that sit directly in the
section root stay un-indented. Nested subdirectories indent one level per depth.

```
── 🖼  Images   7 selected · 0 excluded
   [ select all ]  [ unselect all ]
   [✓] douglas-portrait-lr198.png        · queued   est. ~2 m
   📁 img-subdir/
      [✓] 76-ball-sign-lr320.png         · queued   est. ~2 m
      [✓] budapest-parliament-lr480.png  · queued   est. ~2 m
      [✓] great-wave-lr600.png           · queued   est. ~2 m
   [✓] nypl-1908-scan-lr480.png          · queued   est. ~2 m
```

The folder header is purely visual — it has no checkbox and the cursor skips over
it. The folder name shown is the **subdirectory's own name**, not the full path.

**Scoped `[a]` / `[n]` selection.** `[a]` (select all) and `[n]` (deselect all) act
only on the items that share the cursor's **section _and_ source subdirectory** —
never a sibling folder, never another media type. With the cursor on a file inside
`📁 img-subdir/`, `[a]` selects exactly the three files in that folder; with the
cursor on a root-level image it selects the root-level images. When a section has
no subdirectories this is simply "all items in the section", as before. The
per-section header buttons (`[ select all ]` / `[ unselect all ]`) remain
section-wide.

---

## Batch completion — open output folder

When a batch finishes (`_run_next` drains the queue), the TUI pops open the output
folder(s) that received new files in the OS file manager — one window per media
type that produced output (`output/images`, `output/video`, …) — so results can be
eyeballed immediately without leaving the terminal.

Opening is **best-effort and non-blocking**: macOS uses `open`, Linux uses
`xdg-open` (the freedesktop standard, present on essentially every desktop) with a
fallback chain of common file managers (`gio`, `nautilus`, `dolphin`, `thunar`,
`nemo`, `pcmanfm`, `caja`). On a headless box where none is found, the run logs
`Output ready in <dir>` and carries on — opening is never a hard dependency.

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
| `a` | Select all unfinished items **in the cursor's section / subdirectory** | row 1 |
| `n` | Deselect all items **in the cursor's section / subdirectory** | row 1 |
| `t` | Invert selection | row 1 |
| `r` | Retry all `✗ failed` items | row 1 |
| `f` | Force re-run focused `✓ done` item | row 1 |
| `R` | Reset: wipe every item's output (file + sidecars) and re-queue all for a clean re-run | row 1 |
| `s` | Start batch | row 2 |
| `p` | Pause / resume active job | row 2 |
| `c` | Cancel active job | row 2 |
| `P` | Cycle quality preset (low → medium → high → xhigh) | row 2 |
| `o` | Options — set scale, model, format, tile, face, engine overrides | row 2 |
| `d` | Change input directory | row 2 |
| `q` | Quit (prompts if jobs are active) | row 2 |

Row 1 = selection/navigation controls. Row 2 = job control + app commands. The split keeps related actions grouped visually.

---

## Video quality presets (`-q`)

| Preset | Engine | Scale | GPU | Speed | Quality |
|---|---|---|---|---|---|
| `fast` | realesr-animevideov3 | 2× | yes | ≥9 fps @320×180 | SRVGGNet compact; fastest AI path |
| `low` | ffmpeg lanczos | 2× | no | ~seconds | smooth interpolation, no AI detail |
| `medium` *(default)* | RealCUGAN | 2× | yes | ~2 min/10 s (320×180) | AI-enhanced, good balance |
| `high` | Real-ESRGAN | 4× | yes | ~2 h/30 s | best quality, highest VRAM use |
| `xhigh` | Real-ESRGAN + NVENC | 4× | yes | ~2 h/30 s | max quality; h264_nvenc re-encode |
| `auto` | — (slides by VRAM) | — | adaptive | — | resolves to one of the above at runtime |

Use `-s` and `-e` to override scale or engine individually (e.g. `-q low -s 4` for ffmpeg at 4×). In the TUI, set the preset via the header `Preset` selector or `[P]`; overrides via `[o]`.

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
