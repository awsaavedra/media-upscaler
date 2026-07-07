#!/usr/bin/env python3
"""media-restore v2 TUI — interactive job queue for image and video upscaling."""
from __future__ import annotations

import asyncio
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from textual import events, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widget import Widget
from textual.widgets import Button, Input, Label, ProgressBar, RichLog, Static

# ── Constants ─────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
INPUT_DIR = PROJECT_ROOT / "input"
OUTPUT_DIR = PROJECT_ROOT / "output"

IMAGE_EXTS = frozenset({".jpg", ".jpeg", ".png", ".webp"})
VIDEO_EXTS = frozenset({".mp4", ".mkv", ".avi", ".mov", ".webm", ".wmv"})

# Seed ETA estimates in seconds per preset, per media type
_ETA_SEEDS: dict[str, dict[str, float]] = {
    "image": {"low": 30.0, "medium": 120.0, "high": 120.0, "xhigh": 300.0},
    "video": {"low": 10.0, "medium": 1320.0, "high": 5400.0, "xhigh": 7200.0},
}

_PRESETS = ["low", "medium", "high", "xhigh"]

SCRIPT_IMAGE = SCRIPT_DIR / "upscale-image.sh"
SCRIPT_VIDEO = SCRIPT_DIR / "upscale-video.sh"


# ── Data model ────────────────────────────────────────────────────────────────

@dataclass
class MediaItem:
    path: Path
    media_type: str       # "image" | "video"
    output_path: Path
    selected: bool = True
    status: str = "queued"  # done | queued | active | failed
    done_mtime: str = ""
    est_seconds: float = 120.0
    error_msg: str = ""
    pct: int = 0
    eta_str: str = ""
    throughput_str: str = ""
    _rate_sum: float = field(default=0.0, repr=False)
    _rate_n: int = field(default=0, repr=False)

    @property
    def checkbox(self) -> str:
        if self.status == "failed":
            return "[✗]"
        return "[✓]" if self.selected else "[ ]"

    @property
    def status_label(self) -> str:
        if not self.selected and self.status not in ("done", "active"):
            return "○ excluded"
        match self.status:
            case "done":
                ts = self.done_mtime[-5:] if len(self.done_mtime) >= 5 else self.done_mtime
                return f"✓ done  {ts}"
            case "active":
                pct = f"▶ active  {self.pct}%"
                eta = f"  {self.eta_str} left" if self.eta_str else ""
                thr = f"  · {self.throughput_str}" if self.throughput_str else ""
                return pct + eta + thr
            case "queued":
                return f"· queued  {_fmt_dur(self.est_seconds)}"
            case "failed":
                return f"✗ failed  {self.error_msg}"
            case _:
                return self.status

    def contributes_eta(self) -> bool:
        return self.selected and self.status == "queued"

    def record_rate(self, rate: float) -> None:
        """Update running average rate for adaptive ETA."""
        self._rate_sum += rate
        self._rate_n += 1

    def avg_rate(self) -> float:
        return self._rate_sum / self._rate_n if self._rate_n else 0.0


# ── Scanning ──────────────────────────────────────────────────────────────────

def _find_output(stem: str, out_dir: Path) -> Path | None:
    for ext in (".png", ".jpg", ".webp", ".mp4", ".mkv"):
        c = out_dir / f"{stem}{ext}"
        if c.exists():
            return c
    return None


def _mtime_str(p: Path) -> str:
    return datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M")


# Output-file detection. Real-ESRGAN writes "{stem}_out.{ext}", video writes the
# exact "{name}". Sidecar/progress paths key off the bare "{stem}", so a finished
# image looks unprocessed unless we also probe the "_out" variant.
_OUT_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".mp4", ".mkv", ".mov", ".webm", ".avi")


def find_completed_output(item: MediaItem) -> Path | None:
    """Real on-disk output for an item, matching the bare name or the Real-ESRGAN
    '_out' suffix. Returns None if nothing is present yet."""
    base = item.output_path
    if base.exists():
        return base
    out_dir = base.parent
    if not out_dir.is_dir():
        return None
    stem = base.stem
    for ext in _OUT_EXTS:
        cand = out_dir / f"{stem}_out{ext}"
        if cand.exists():
            return cand
    return None


def output_artifacts(item: MediaItem) -> list[Path]:
    """Every on-disk file a completed run leaves for an item: the upscaled output
    plus its progress/audit sidecars. Naming differs by media type (images write
    '{stem}_out.{ext}' and '{stem}.audit.json'; video writes '{name}' and
    '{name}.audit.json'), so we enumerate all candidates and let the caller skip
    the ones that don't exist. Used by reset to wipe a prior run clean."""
    out = item.output_path
    out_dir = out.parent
    candidates = [
        out,                                   # bare output / video result
        Path(f"{out}.progress.json"),          # '{stem}.png.progress.json' / '{name}.progress.json'
        Path(f"{out}.audit.json"),             # video audit '{name}.audit.json'
        out_dir / f"{out.stem}.audit.json",    # image audit '{stem}.audit.json'
    ]
    real = find_completed_output(item)         # Real-ESRGAN '{stem}_out.{ext}'
    if real is not None:
        candidates.append(real)
    seen: dict[Path, None] = {}
    for p in candidates:
        seen.setdefault(p, None)
    return list(seen)


# Opening the output folder when a batch finishes. xdg-open is the freedesktop
# standard and present on essentially every Linux desktop; the rest are
# belt-and-suspenders fallbacks for stripped-down or unusual setups. macOS uses
# `open`, which always exists. `gio open` takes a sub-verb, hence the special case.
_LINUX_OPENERS = ("xdg-open", "gio", "nautilus", "dolphin", "thunar", "nemo", "pcmanfm", "caja")


def file_manager_commands(
    path: Path, system: str | None = None, which=shutil.which
) -> list[list[str]]:
    """Ordered file-manager open commands to try for *path* on the given OS. Pure
    (no spawning) so it can be unit-tested; `open_in_file_manager` runs the first
    that works. Empty list means no opener is available (e.g. a headless box)."""
    system = system or platform.system()
    p = str(path)
    if system == "Darwin":
        return [["open", p]]
    if system == "Windows":
        return [["explorer", p]]
    cmds: list[list[str]] = []
    for name in _LINUX_OPENERS:
        exe = which(name)
        if not exe:
            continue
        cmds.append([exe, "open", p] if name == "gio" else [exe, p])
    return cmds


def open_in_file_manager(path: Path) -> bool:
    """Open *path* in the OS file manager, best-effort and non-blocking. Returns
    False when nothing could be launched — callers treat this as a nicety, never
    a hard dependency."""
    for cmd in file_manager_commands(path):
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except OSError:
            continue
    return False


# Liveness for "running" sidecars. A job that died uncleanly (TUI closed mid-run,
# crash, kill) leaves its last "running" file on disk; without a liveness check the
# TUI trusts it forever and the item is stuck "▶ active" (the gradient zombie).
SIDECAR_STALE_SECS = 90.0


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True   # exists, owned by another user
    except OSError:
        return False
    return True


def sidecar_job_alive(
    data: dict, sidecar_mtime: float, now: float,
    stale_secs: float = SIDECAR_STALE_SECS,
) -> bool:
    """Is the process that wrote this 'running' sidecar still alive? PID liveness
    is authoritative when present; otherwise fall back to mtime freshness for
    legacy (pid-less) sidecars — a live job rewrites its sidecar every frame/file."""
    pid = data.get("pid")
    if pid is not None:
        try:
            return _pid_alive(int(pid))
        except (TypeError, ValueError):
            pass
    return (now - sidecar_mtime) <= stale_secs


def scan_images(
    preset: str,
    input_dir: Path = INPUT_DIR,
    output_dir: Path = OUTPUT_DIR,
) -> list[MediaItem]:
    src = input_dir / "images"
    dst = output_dir / "images"
    items: list[MediaItem] = []
    if not src.exists():
        return items
    est = _ETA_SEEDS["image"].get(preset, 120.0)
    for p in sorted(src.rglob("*")):
        if p.suffix.lower() not in IMAGE_EXTS or "gt" in p.parts:
            continue
        rel = p.relative_to(src)
        out_dir = dst / rel.parent
        out = _find_output(p.stem, out_dir) or (out_dir / (p.stem + ".png"))
        item = MediaItem(path=p, media_type="image", output_path=out, est_seconds=est)
        real = find_completed_output(item)
        if real is not None:
            item.status = "done"
            item.done_mtime = _mtime_str(real)
        items.append(item)
    return items


def scan_video(
    preset: str,
    input_dir: Path = INPUT_DIR,
    output_dir: Path = OUTPUT_DIR,
) -> list[MediaItem]:
    src = input_dir / "video"
    dst = output_dir / "video"
    items: list[MediaItem] = []
    if not src.exists():
        return items
    est = _ETA_SEEDS["video"].get(preset, 1320.0)
    first_unfinished = True
    for p in sorted(src.rglob("*")):
        if p.suffix.lower() not in VIDEO_EXTS:
            continue
        out = dst / p.name
        item = MediaItem(path=p, media_type="video", output_path=out, est_seconds=est)
        real = find_completed_output(item)
        if real is not None:
            item.status = "done"
            item.done_mtime = _mtime_str(real)
        else:
            item.selected = first_unfinished
            first_unfinished = False
        items.append(item)
    return items


def scan_all(
    preset: str,
    input_dir: Path = INPUT_DIR,
    output_dir: Path = OUTPUT_DIR,
) -> list[MediaItem]:
    return scan_images(preset, input_dir, output_dir) + scan_video(preset, input_dir, output_dir)


# ── ETA helpers ───────────────────────────────────────────────────────────────

def _fmt_mins(s: float) -> str:
    m = max(1, round(s / 60))
    h, r = divmod(m, 60)
    return f"~{h} h {r:02d} m" if h else f"~{m} m"


def _fmt_dur(s: float) -> str:
    s = int(s)
    h, r = divmod(s, 3600)
    m, sec = divmod(r, 60)
    if h:
        return f"{h}h {m:02d}m"
    return f"{m}m {sec:02d}s" if m else f"{sec}s"


def build_eta_text(items: list[MediaItem], run_start: float | None) -> str:
    queued = [i for i in items if i.contributes_eta()]
    total_s = sum(i.est_seconds for i in queued)
    if run_start is None:
        if not queued:
            return "No items selected  ·  [a] select all  ·  [s] to start"
        return f"Total ETA  {_fmt_mins(total_s)}   ({_breakdown(queued)})"
    elapsed = time.time() - run_start
    active = [i for i in items if i.status == "active"]
    if not queued:
        if active:
            name = active[0].path.name
            return f"Elapsed  {_fmt_dur(elapsed)}  ·  Processing {name} (last item)…"
        return f"Elapsed  {_fmt_dur(elapsed)}  ·  Queue complete"
    suffix = f"  ·  {len(active)} active" if active else ""
    return (
        f"Elapsed  {_fmt_dur(elapsed)}  ·  "
        f"Total ETA  {_fmt_mins(total_s)} remaining   ({len(queued)} queued{suffix})"
    )


def _breakdown(queued: list[MediaItem]) -> str:
    imgs = [i for i in queued if i.media_type == "image"]
    vids = [i for i in queued if i.media_type == "video"]
    parts: list[str] = []
    if imgs:
        avg = sum(i.est_seconds for i in imgs) / len(imgs)
        parts.append(f"{len(imgs)} img × {_fmt_mins(avg)}")
    if vids:
        avg = sum(i.est_seconds for i in vids) / len(vids)
        parts.append(f"{len(vids)} vid × {_fmt_mins(avg)}")
    return "  +  ".join(parts)


def section_counts(items: list[MediaItem]) -> str:
    done = sum(1 for i in items if i.status == "done")
    active = sum(1 for i in items if i.status == "active")
    queued = sum(1 for i in items if i.status == "queued" and i.selected)
    failed = sum(1 for i in items if i.status == "failed")
    excl = sum(1 for i in items if not i.selected and i.status not in ("done", "active"))
    parts: list[str] = []
    if done:   parts.append(f"{done} done")
    if active: parts.append(f"{active} active")
    if queued: parts.append(f"{queued} queued")
    if failed: parts.append(f"{failed} failed")
    if excl:   parts.append(f"{excl} excluded")
    return "  ·  ".join(parts)


# ── GPU polling ───────────────────────────────────────────────────────────────

def poll_gpu() -> dict:
    try:
        raw = subprocess.check_output(
            ["nvidia-smi",
             "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,clocks.sm",
             "--format=csv,noheader,nounits"],
            text=True, stderr=subprocess.DEVNULL, timeout=1,
        )
        p = [x.strip() for x in raw.strip().split(",")]
        return {
            "util": int(p[0]), "mem_used": int(p[1]),
            "mem_total": int(p[2]), "temp": int(p[3]), "clock": int(p[4]),
        }
    except Exception:
        return {}


_gpu_peak_clock: int = 0  # highest SM clock observed this session; used for throttle detection


def render_gpu_text(gpu: dict) -> str:
    global _gpu_peak_clock
    if not gpu:
        return "GPU stats unavailable"
    w = 14
    uf = round(gpu["util"] / 100 * w)
    vf = round(gpu["mem_used"] / max(gpu["mem_total"], 1) * w)
    ub = "█" * uf + "░" * (w - uf)
    vb = "█" * vf + "░" * (w - vf)
    gu = gpu["mem_used"] / 1024
    gt_gb = gpu["mem_total"] / 1024
    clock = gpu["clock"]
    temp = gpu["temp"]
    if clock > _gpu_peak_clock:
        _gpu_peak_clock = clock
    throttle = (
        _gpu_peak_clock > 0
        and temp >= 85
        and clock < _gpu_peak_clock * 0.85
    )
    throttle_flag = "  ⚠ THROTTLING" if throttle else ""
    return (
        f"Util   {ub}  {gpu['util']:3d} %\n"
        f"VRAM   {vb}  {gu:.1f} / {gt_gb:.1f} GB\n"
        f"Temp   {temp} °C  ·  Clock  {clock} MHz{throttle_flag}"
    )


# ── Progress line parsing ─────────────────────────────────────────────────────

_IMG_TEST_RE = re.compile(r"Testing (\d+)")
_IMG_TILE_RE = re.compile(r"Tile (\d+)/(\d+)")
_VID_FRAME_RE = re.compile(
    r"frame=(\d+)/(\d+)[^;]*;\s*fps=([^;]+);\s*elapsed=([^;]+);\s*remaining=(\S+)"
)


def parse_image_progress(line: str, total_files: int) -> dict | None:
    m = _IMG_TEST_RE.search(line)
    if m and total_files > 0:
        n = int(m.group(1)) + 1
        return {"pct": min(99, round(n / total_files * 100)), "throughput": ""}
    m = _IMG_TILE_RE.search(line)
    if m:
        k, n = int(m.group(1)), int(m.group(2))
        return {"pct": None, "throughput": f"tile {k}/{n}"}
    return None


def normalize_sidecar(data: dict) -> dict:
    """Normalize a `{output}.progress.json` payload into TUI fields.

    The scripts emit different throughput keys: upscale-video.sh writes `fps`,
    upscale-image.sh writes neither. Unify them to a single `throughput` string
    so the reattach poller has one authoritative shape to consume.
    """
    out: dict = {"status": data.get("status", "running")}
    if "pct" in data:
        out["pct"] = int(data["pct"])
    throughput = data.get("throughput")
    if throughput is None and data.get("fps") not in (None, "", "0"):
        throughput = f"{data['fps']} fps"
    if throughput:
        out["throughput"] = str(throughput)
    remaining = data.get("remaining")
    if remaining:
        out["eta"] = str(remaining)
    return out


def parse_video_progress(line: str) -> dict | None:
    clean = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", line).replace("\r", "")
    m = _VID_FRAME_RE.search(clean)
    if not m:
        return None
    cur, tot, fps, _elapsed, remaining = m.groups()
    pct = round(int(cur) / max(int(tot), 1) * 100)
    return {"pct": pct, "throughput": f"{fps.strip()} fps", "eta": remaining.strip()}


def split_progress_stream(buf: str) -> tuple[list[tuple[str, bool]], str]:
    """Split a raw subprocess buffer on CR *and* LF, returning (segment, is_log)
    pairs plus the trailing incomplete remainder.

    video2x redraws its progress bar in place with '\\r' and no newline, so a
    plain readline() never yields it until the job ends. A '\\n'-terminated
    segment is a real log line (is_log=True); a '\\r'-terminated one is a
    progress redraw (is_log=False — parse it, but don't spam the log).
    """
    segments: list[tuple[str, bool]] = []
    pos = 0
    while True:
        m = re.search(r"[\r\n]", buf[pos:])
        if m is None:
            break
        start = pos + m.start()
        seg = buf[pos:start].strip()
        if seg:
            segments.append((seg, buf[start] == "\n"))
        pos = start + 1
    return segments, buf[pos:]


# ── Widgets ───────────────────────────────────────────────────────────────────

_ROW_CSS = """
ChecklistRow {
    height: 1;
    padding: 0 1;
    color: $text;
}
ChecklistRow.highlighted { background: $primary 30%; }
ChecklistRow.done        { color: $text-muted; }
ChecklistRow.active      { color: $success; }
ChecklistRow.failed      { color: $error; }
DirHeader {
    height: 1;
    padding: 0 1;
    color: $secondary;
    text-style: bold;
}
"""


class ChecklistRow(Widget):
    can_focus = False  # App manages cursor/highlighting manually
    _render_markup = False  # [✓] [✗] [ ] are literal characters, not markup

    def __init__(self, item: MediaItem, idx: int, indent: int = 0) -> None:
        super().__init__(id=f"row-{idx}")
        self.item = item
        self.idx = idx
        self._indent = indent  # nesting depth under a DirHeader (0 = section root)

    def render(self) -> str:
        pad = "   " * self._indent  # align files beneath their 📁 folder
        name = self.item.path.name
        if len(name) > 18:
            name = name[:16] + "…"
        return f"{pad}{self.item.checkbox} {name:<18}  {self.item.status_label}"

    def sync_classes(self) -> None:
        self.remove_class("done", "active", "failed")
        if self.item.status == "done":
            self.add_class("done")
        elif self.item.status == "active":
            self.add_class("active")
        elif self.item.status == "failed":
            self.add_class("failed")
        self.refresh()


_DIR_ICON = "📁"


class DirHeader(Static):
    """A folder row inside a media section, like a file browser: shows the
    subdirectory's own name (not the full path) with a 📁 icon, and the images
    that live in it are mounted indented beneath it. Purely visual — it is not a
    MediaItem, carries no checkbox, and is skipped by the cursor."""
    _render_markup = False  # 📁 is a literal glyph, not markup

    def __init__(self, name: str, depth: int = 0) -> None:
        super().__init__()
        self._name = name
        self._depth = depth

    def render(self) -> str:
        pad = "   " * self._depth
        return f"{pad}{_DIR_ICON} {self._name}/"


# Row-header icons per media type: picture, video, audio.
_SEC_ICONS = {"image": "🖼", "video": "🎬", "audio": "🎵"}

_SEC_CSS = """
SectionHeader {
    height: 2;
    background: $panel-darken-2;
    padding: 0 1;
}
SectionHeader.inactive { background: $panel-darken-3; }
SectionHeader.inactive .sec-label { color: $text-disabled; }
.sec-label    { width: auto; margin-right: 2; }
.sec-count    { width: 1fr; color: $text-muted; }
.sec-inactive { width: 1fr; color: $text-disabled; text-style: italic; }
.sec-btn      { height: 1; min-width: 14; border: none; background: $surface; margin-right: 1; }
"""


class SectionHeader(Horizontal):
    def __init__(self, title: str, media_type: str, inactive: bool = False) -> None:
        super().__init__()
        self._title = title
        self._mtype = media_type
        self._inactive = inactive
        if inactive:
            self.add_class("inactive")

    def compose(self) -> ComposeResult:
        icon = _SEC_ICONS.get(self._mtype, "")
        yield Label(f"── {icon}  {self._title}", classes="sec-label")
        if self._inactive:
            # Greyed, no select/start controls — section is not yet usable.
            yield Label("inactive — audio upscaling not yet available",
                        classes="sec-inactive")
            return
        yield Label("", id=f"sec-count-{self._mtype}", classes="sec-count")
        yield Button("select all",   id=f"sel-{self._mtype}",   classes="sec-btn")
        yield Button("unselect all", id=f"unsel-{self._mtype}", classes="sec-btn")

    def update_counts(self, items: list[MediaItem]) -> None:
        if self._inactive:
            return
        text = section_counts([i for i in items if i.media_type == self._mtype])
        try:
            self.query_one(f"#sec-count-{self._mtype}", Label).update(text)
        except Exception:
            pass


_ACTIVE_JOB_CSS = """
ActiveJobPanel {
    height: 7;
    padding: 1;
    border-bottom: solid $panel-darken-1;
}
#job-name   { color: $text; margin-bottom: 1; }
#job-detail { color: $text-muted; }
"""


class ActiveJobPanel(Widget):
    def compose(self) -> ComposeResult:
        yield Label("No active job", id="job-name")
        yield Static("─" * 42, id="job-sep")
        yield ProgressBar(id="job-bar", show_eta=False, show_percentage=True)
        yield Label("Press [s] to start", id="job-detail")

    def set_idle(self) -> None:
        self.query_one("#job-name", Label).update("No active job")
        self.query_one("#job-bar", ProgressBar).update(progress=0, total=100)
        self.query_one("#job-detail", Label).update("Press [s] to start")

    def update_job(self, item: MediaItem, elapsed: float = 0.0) -> None:
        self.query_one("#job-name", Label).update(item.path.name)
        if item.pct is not None:
            self.query_one("#job-bar", ProgressBar).update(progress=item.pct, total=100)
        # Elapsed always ticks while a job runs, so the panel is never ambiguous
        # about whether work is happening — even before the first progress line.
        parts: list[str] = []
        if elapsed > 0:
            parts.append(f"running {_fmt_dur(elapsed)}")
        if item.throughput_str:
            parts.append(item.throughput_str)
        if item.eta_str:
            parts.append(f"{item.eta_str} left")
        self.query_one("#job-detail", Label).update("  ·  ".join(parts) or "starting…")


_GPU_CSS = """
GpuPanel {
    height: 5;
    padding: 1;
    border-bottom: solid $panel-darken-1;
    color: $text-muted;
}
"""


class GpuPanel(Static):
    _render_markup = False  # ASCII bar chars (█ ░) are plain text


# ── Keymap ─────────────────────────────────────────────────────────────────────
# Single source of truth for key bindings, the footer hint bar, and the ? help
# overlay. Defining a key here registers it everywhere at once, so the visible
# hints can never drift from the actual bindings.

@dataclass(frozen=True)
class KeyAction:
    binds: tuple[tuple[str, str], ...]  # (textual_key, action_name) pairs to register
    display: str                         # key glyph shown to the user, e.g. "↑↓", "Space"
    label: str                           # short footer verb, e.g. "Move", "Toggle"
    help: str                            # full one-line description for the ? overlay
    group: str                           # footer group heading: "SELECT" | "RUN"


_KEYMAP: tuple[KeyAction, ...] = (
    KeyAction((("up", "nav_up"), ("down", "nav_down")), "↑↓", "Move",
              "Move cursor up / down", "SELECT"),
    KeyAction((("space", "toggle_item"),), "Space", "Toggle",
              "Toggle the highlighted item in / out of the queue", "SELECT"),
    KeyAction((("a", "select_all"),), "a", "All",
              "Select all items in the cursor's section / subdirectory", "SELECT"),
    KeyAction((("n", "select_none"),), "n", "None",
              "Unselect items in the cursor's section / subdirectory", "SELECT"),
    KeyAction((("t", "invert_sel"),), "t", "Invert",
              "Invert the current selection", "SELECT"),
    KeyAction((("r", "retry_failed"),), "r", "Retry",
              "Re-queue every failed item", "SELECT"),
    KeyAction((("f", "force_redo"),), "f", "Redo",
              "Force re-run the highlighted already-done item", "SELECT"),
    KeyAction((("R", "reset"),), "R", "Reset",
              "Re-queue every item — re-run all outputs", "SELECT"),
    KeyAction((("s", "start_batch"),), "s", "Start",
              "Start processing the queued items", "RUN"),
    KeyAction((("p", "pause_resume"),), "p", "Pause",
              "Pause / resume the active job", "RUN"),
    KeyAction((("c", "cancel_job"),), "c", "Cancel",
              "Cancel the active job (it returns to the queue)", "RUN"),
    KeyAction((("P", "cycle_preset"),), "P", "Preset",
              "Cycle quality preset: low → medium → high → xhigh", "RUN"),
    KeyAction((("o", "options"),), "o", "Options",
              "Open the per-flag overrides modal", "RUN"),
    KeyAction((("d", "change_dir"),), "d", "Dir",
              "Change the input directory and rescan", "RUN"),
    KeyAction((("question_mark", "help"),), "?", "Help",
              "Show / hide this key reference", "RUN"),
    KeyAction((("q", "request_quit"),), "q", "Quit",
              "Quit (blocked while a job is active)", "RUN"),
)


def build_bindings() -> list[Binding]:
    """Register every keymap entry as a Textual binding (hidden — the footer
    and ? overlay render the hints, not Textual's own Footer widget)."""
    return [
        Binding(key, action, show=False)
        for entry in _KEYMAP
        for (key, action) in entry.binds
    ]


def footer_rows() -> list[str]:
    """One footer line per group, e.g. 'SELECT  ↑↓=Move  Space=Toggle  …'."""
    groups: dict[str, list[str]] = {}
    order: list[str] = []
    for entry in _KEYMAP:
        if entry.group not in groups:
            groups[entry.group] = []
            order.append(entry.group)
        groups[entry.group].append(f"{entry.display}={entry.label}")
    return [f"{name:<7} " + "  ".join(groups[name]) for name in order]


def help_rows() -> list[tuple[str, str]]:
    """(key glyph, full description) for every action, for the ? overlay."""
    return [(entry.display, entry.help) for entry in _KEYMAP]


_KEY_CSS = """
KeyHintsBar {
    height: 2;
    background: $panel-darken-2;
    color: $text-muted;
    padding: 0 1;
}
"""


class KeyHintsBar(Static):
    _render_markup = False  # ↑↓ Space etc. are literal key hint text

    def render(self) -> str:
        return "\n".join(footer_rows())


_ETA_CSS = """
EtaBar {
    height: 1;
    background: $panel-darken-1;
    color: $text;
    padding: 0 1;
}
"""


class EtaBar(Static):
    _render_markup = False  # [a] [s] in hint text are literal, not markup


# ── Options modal ────────────────────────────────────────────────────────────

_OPT_DEFAULTS: dict[str, str] = {
    "img_scale": "", "img_model": "", "img_format": "", "img_tile": "",
    "img_face": "0", "vid_scale": "", "vid_engine": "",
    "vid_dedup": "0", "vid_interpolate": "", "vid_thermal": "",
}

_IMG_FORMATS = ["", "png", "jpg", "webp"]
_VID_ENGINES = ["", "realesrgan", "realcugan", "anime4k"]


class OptionsModal(ModalScreen):
    CSS = """
    OptionsModal { align: center middle; }
    #opt-dialog {
        width: 66;
        height: auto;
        padding: 1 2;
        border: thick $primary;
        background: $surface;
    }
    .opt-section { color: $text-muted; margin-top: 1; margin-bottom: 0; }
    .opt-row { height: 1; margin-bottom: 0; }
    .opt-lbl { width: 10; }
    .opt-inp { width: 14; }
    .opt-hint { width: 1fr; color: $text-muted; }
    #opt-btns { margin-top: 1; }
    .opt-btn { min-width: 10; margin-right: 1; }
    """

    def __init__(self, current: dict[str, str]) -> None:
        super().__init__()
        self._current = dict(current)

    def compose(self) -> ComposeResult:
        with Vertical(id="opt-dialog"):
            yield Label("── Image overrides  (blank = preset default)", classes="opt-section")
            with Horizontal(classes="opt-row"):
                yield Label("scale",  classes="opt-lbl")
                yield Input(value=self._current["img_scale"],  id="img_scale",  classes="opt-inp")
                yield Label("integer, e.g. 2 or 4",           classes="opt-hint")
            with Horizontal(classes="opt-row"):
                yield Label("model",  classes="opt-lbl")
                yield Input(value=self._current["img_model"],  id="img_model",  classes="opt-inp")
                yield Label("name or /abs/path/to/model.pth", classes="opt-hint")
            with Horizontal(classes="opt-row"):
                yield Label("format", classes="opt-lbl")
                yield Input(value=self._current["img_format"], id="img_format", classes="opt-inp")
                yield Label("png | jpg | webp",               classes="opt-hint")
            with Horizontal(classes="opt-row"):
                yield Label("tile",   classes="opt-lbl")
                yield Input(value=self._current["img_tile"],   id="img_tile",   classes="opt-inp")
                yield Label("0 = auto-VRAM",                  classes="opt-hint")
            with Horizontal(classes="opt-row"):
                yield Label("face",   classes="opt-lbl")
                yield Input(value=self._current["img_face"],   id="img_face",   classes="opt-inp")
                yield Label("1 = on  (GFPGAN; slow)",         classes="opt-hint")
            yield Label("── Video overrides", classes="opt-section")
            with Horizontal(classes="opt-row"):
                yield Label("scale",     classes="opt-lbl")
                yield Input(value=self._current["vid_scale"],     id="vid_scale",     classes="opt-inp")
                yield Label("integer override",                   classes="opt-hint")
            with Horizontal(classes="opt-row"):
                yield Label("engine",    classes="opt-lbl")
                yield Input(value=self._current["vid_engine"],    id="vid_engine",    classes="opt-inp")
                yield Label("realesrgan | realcugan | anime4k | tensorrt", classes="opt-hint")
            with Horizontal(classes="opt-row"):
                yield Label("dedup",     classes="opt-lbl")
                yield Input(value=self._current["vid_dedup"],     id="vid_dedup",     classes="opt-inp")
                yield Label("1 = skip duplicate frames (mpdecimate)",     classes="opt-hint")
            with Horizontal(classes="opt-row"):
                yield Label("interpol.", classes="opt-lbl")
                yield Input(value=self._current["vid_interpolate"], id="vid_interpolate", classes="opt-inp")
                yield Label("2x = double framerate (RIFE / minterpolate)", classes="opt-hint")
            with Horizontal(classes="opt-row"):
                yield Label("thermal",   classes="opt-lbl")
                yield Input(value=self._current["vid_thermal"],   id="vid_thermal",   classes="opt-inp")
                yield Label("conservative | balanced | performance", classes="opt-hint")
            with Horizontal(id="opt-btns"):
                yield Button("Apply",  id="opt-apply",  classes="opt-btn", variant="primary")
                yield Button("Clear",  id="opt-clear",  classes="opt-btn")
                yield Button("Cancel", id="opt-cancel", classes="opt-btn")

    def _collect(self) -> dict[str, str]:
        vals: dict[str, str] = {}
        for key in _OPT_DEFAULTS:
            try:
                vals[key] = self.query_one(f"#{key}", Input).value.strip()
            except Exception:
                vals[key] = self._current.get(key, "")
        return vals

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "opt-apply":
            self.dismiss(self._collect())
        elif event.button.id == "opt-clear":
            self.dismiss(dict(_OPT_DEFAULTS))
        else:
            self.dismiss(None)

    def on_key(self, event: events.Key) -> None:
        if event.key == "escape":
            self.dismiss(None)


# ── Dir prompt modal ─────────────────────────────────────────────────────────

class DirPrompt(ModalScreen):
    CSS = """
    DirPrompt { align: center middle; }
    #dir-dialog {
        width: 64;
        height: auto;
        padding: 1 2;
        border: thick $primary;
        background: $surface;
    }
    #dir-label { margin-bottom: 1; }
    """

    def compose(self) -> ComposeResult:
        with Vertical(id="dir-dialog"):
            yield Label("Enter input directory path:", id="dir-label")
            yield Input(placeholder="/path/to/input", id="dir-input")

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value.strip() or None)

    def on_key(self, event: events.Key) -> None:
        if event.key == "escape":
            self.dismiss(None)


# ── Help overlay ───────────────────────────────────────────────────────────────

class HelpScreen(ModalScreen):
    """Full key reference. Rendered from _KEYMAP so it never drifts."""

    CSS = """
    HelpScreen { align: center middle; }
    #help-dialog {
        width: 60;
        height: auto;
        padding: 1 2;
        border: thick $primary;
        background: $surface;
    }
    #help-title { text-style: bold; margin-bottom: 1; }
    .help-row { height: 1; }
    .help-key { width: 8; color: $accent; }
    .help-desc { width: 1fr; color: $text; }
    #help-foot { margin-top: 1; color: $text-muted; }
    """

    def compose(self) -> ComposeResult:
        with Vertical(id="help-dialog"):
            yield Label("Keyboard reference", id="help-title")
            for glyph, desc in help_rows():
                with Horizontal(classes="help-row"):
                    yield Label(glyph, classes="help-key", markup=False)
                    yield Label(desc, classes="help-desc", markup=False)
            yield Label("?, Esc or q to close", id="help-foot")

    def on_key(self, event: events.Key) -> None:
        if event.key in ("escape", "question_mark", "q", "enter"):
            self.dismiss(None)


# ── App ───────────────────────────────────────────────────────────────────────

_APP_CSS = """
Screen { layout: vertical; background: $background; }

#header-bar {
    height: 1;
    background: $panel-darken-2;
    color: $text-muted;
    padding: 0 1;
}
#body { height: 1fr; }
#files-pane {
    width: 55%;
    border-right: solid $panel-darken-1;
}
#img-list, #vid-list { height: auto; }
#right-col { width: 45%; }
#log-pane  { height: 1fr; }
""" + _ROW_CSS + _SEC_CSS + _ACTIVE_JOB_CSS + _GPU_CSS + _KEY_CSS + _ETA_CSS


class MediaRestoreApp(App):
    CSS = _APP_CSS
    TITLE = "media-restore v2"

    BINDINGS = build_bindings()  # generated from _KEYMAP — see the Keymap section

    def __init__(self, input_dir: Path = INPUT_DIR, preset: str = "medium",
                 output_dir: Path = OUTPUT_DIR) -> None:
        super().__init__()
        self._input_dir = input_dir
        self._output_dir = output_dir
        self._preset = preset
        self._items: list[MediaItem] = []
        self._cursor: int = 0
        self._run_start: float | None = None
        self._active_item: MediaItem | None = None
        self._job_start: float | None = None
        self._job_proc: asyncio.subprocess.Process | None = None
        self._paused = False
        self._gpu: dict = {}
        self._actual_secs: dict[str, list[float]] = {}
        self._opts: dict[str, str] = dict(_OPT_DEFAULTS)
        self._run_output_dirs: set[Path] = set()  # output folders to open at batch end

    # ── Layout ───────────────────────────────────────────────────────────────

    def compose(self) -> ComposeResult:
        yield Static(
            f"Preset [{self._preset} ▾]   Input [{self._input_dir} ▶]",
            id="header-bar",
            markup=False,
        )
        with Horizontal(id="body"):
            with VerticalScroll(id="files-pane"):
                yield SectionHeader("Images", "image")
                yield Vertical(id="img-list")
                yield SectionHeader("Video", "video")
                yield Vertical(id="vid-list")
                yield SectionHeader("Audio", "audio", inactive=True)
                yield Vertical(id="aud-list")
            with Vertical(id="right-col"):
                yield ActiveJobPanel(id="active-job")
                yield GpuPanel("Polling GPU…", id="gpu-panel")
                yield RichLog(id="log-pane", highlight=True, markup=True, max_lines=200)
        yield EtaBar("", id="eta-bar")
        yield KeyHintsBar()

    def on_mount(self) -> None:
        self._items = scan_all(self._preset, self._input_dir, self._output_dir)
        self._populate_rows()
        self._refresh_cursor(0)
        self._update_ui()
        self.query_one(ActiveJobPanel).set_idle()
        self.query_one(GpuPanel).update("waiting for job…")
        self.set_interval(2.0, self._tick_gpu)
        self.set_interval(5.0, self._tick_sidecars)
        self.set_interval(1.0, self._tick_active)
        self._reattach_sidecars()

    def _tick_active(self) -> None:
        """Tick the active job's elapsed clock every second so the panel visibly
        moves even when no progress line has arrived yet."""
        item = self._active_item
        if item is None or self._job_start is None or item.status != "active":
            return
        self.query_one(ActiveJobPanel).update_job(item, time.time() - self._job_start)
        self._update_eta()

    def _section_root(self, media_type: str) -> Path:
        sub = {"image": "images", "video": "video", "audio": "audio"}[media_type]
        return self._input_dir / sub

    def _section_output_root(self, media_type: str) -> Path:
        sub = {"image": "images", "video": "video", "audio": "audio"}[media_type]
        return self._output_dir / sub

    def _open_output_dirs(self) -> None:
        """When a batch finishes, pop open the output folder(s) that received new
        files so the user can eyeball results right away — one window per media
        type (output/images, output/video, …). Best-effort: a box with no file
        manager just logs a note, never errors."""
        dirs = sorted(d for d in self._run_output_dirs if d.is_dir())
        self._run_output_dirs = set()
        for d in dirs:
            if open_in_file_manager(d):
                self._log(f"Opened output folder [bold]{d}[/bold]")
            else:
                self._log(f"Output ready in {d} (no file manager found to open it)")

    def _item_subdir_parts(self, item: MediaItem) -> tuple[str, ...]:
        """The item's source subdirectory relative to its section root, as path
        parts. Empty tuple means the item sits directly in the section root."""
        try:
            rel = item.path.parent.relative_to(self._section_root(item.media_type))
        except ValueError:
            return ()
        return () if rel == Path(".") else rel.parts

    def _populate_rows(self) -> None:
        img_list = self.query_one("#img-list", Vertical)
        vid_list = self.query_one("#vid-list", Vertical)
        # Mount a 📁 folder header the first time each subdirectory appears, so the
        # section reads like a file browser: folders named, their files indented.
        seen_dirs: set[tuple[str, str]] = set()
        for idx, item in enumerate(self._items):
            target = img_list if item.media_type == "image" else vid_list
            parts = self._item_subdir_parts(item)
            for depth, name in enumerate(parts):
                key = (item.media_type, "/".join(parts[: depth + 1]))
                if key not in seen_dirs:
                    seen_dirs.add(key)
                    target.mount(DirHeader(name, depth))
            row = ChecklistRow(item, idx, indent=len(parts))
            row.sync_classes()
            target.mount(row)

    # ── Cursor management ─────────────────────────────────────────────────────

    def _focusable_indices(self) -> list[int]:
        return [i for i, it in enumerate(self._items) if it.status != "done"]

    def _refresh_cursor(self, new_idx: int) -> None:
        focusable = self._focusable_indices()
        if not focusable:
            return
        self._cursor = max(0, min(new_idx, len(focusable) - 1))
        actual = focusable[self._cursor]
        for row in self.query(ChecklistRow):
            row.remove_class("highlighted")
        try:
            row = self.query_one(f"#row-{actual}", ChecklistRow)
            row.add_class("highlighted")
            row.scroll_visible()
        except Exception:
            pass

    def _current_item(self) -> MediaItem | None:
        focusable = self._focusable_indices()
        if not focusable:
            return None
        return self._items[focusable[self._cursor]]

    # ── Periodic updates ──────────────────────────────────────────────────────

    def _tick_gpu(self) -> None:
        self._gpu = poll_gpu()
        text = render_gpu_text(self._gpu)
        self.query_one(GpuPanel).update(text)

    def _reattach_sidecars(self) -> None:
        """On startup, mark items with a live progress sidecar as active."""
        changed = False
        for item in self._items:
            if item.status in ("done", "active"):
                continue
            sidecar = Path(str(item.output_path) + ".progress.json")
            if not sidecar.exists():
                continue
            try:
                data = json.loads(sidecar.read_text())
                if data.get("status") == "running":
                    if sidecar_job_alive(data, sidecar.stat().st_mtime, time.time()):
                        item.status = "active"
                        item.pct = int(data.get("pct", 0))
                    else:
                        # Dead/finished job left a stale 'running' file — reconcile.
                        self._reconcile_dead(item)
                    changed = True
            except Exception:
                pass
        if changed:
            self._update_ui()

    def _reconcile_dead(self, item: MediaItem) -> None:
        """A 'running' sidecar whose job is no longer alive: mark done if the
        output landed, else reset to queued so it can re-run. Never leave active."""
        real = find_completed_output(item)
        if real is not None:
            item.status = "done"
            item.done_mtime = _mtime_str(real)
        else:
            item.status = "queued"
            item.pct = 0
        item.throughput_str = ""
        item.eta_str = ""

    def _tick_sidecars(self) -> None:
        """Poll progress sidecars for items active from a previous session."""
        if self._job_proc is not None:
            return  # live subprocess — TUI tracks progress directly
        changed = False
        for item in self._items:
            if item.status != "active":
                continue
            sidecar = Path(str(item.output_path) + ".progress.json")
            if not sidecar.exists():
                self._reconcile_dead(item)
                changed = True
                continue
            try:
                data = json.loads(sidecar.read_text())
                status = data.get("status", "running")
                if status == "done":
                    item.status = "done"
                    item.done_mtime = datetime.now().strftime("%Y-%m-%d %H:%M")
                    changed = True
                elif status == "failed":
                    item.status = "failed"
                    item.error_msg = str(data.get("error", "script error"))
                    changed = True
                elif not sidecar_job_alive(data, sidecar.stat().st_mtime, time.time()):
                    # Sidecar still says 'running' but the job is gone — reconcile.
                    self._reconcile_dead(item)
                    changed = True
                else:
                    norm = normalize_sidecar(data)
                    new_pct = norm.get("pct", item.pct)
                    if new_pct != item.pct:
                        item.pct = new_pct
                        changed = True
                    if norm.get("throughput"):
                        item.throughput_str = norm["throughput"]
                    if norm.get("eta"):
                        item.eta_str = norm["eta"]
            except Exception:
                pass
        if changed:
            self._update_ui()

    def _update_ui(self) -> None:
        self._update_eta()
        self._update_section_counts()
        for row in self.query(ChecklistRow):
            row.sync_classes()
            row.refresh()

    def _update_eta(self) -> None:
        text = build_eta_text(self._items, self._run_start)
        self.query_one(EtaBar).update(text)

    def _update_section_counts(self) -> None:
        for hdr in self.query(SectionHeader):
            hdr.update_counts(self._items)

    # ── Selection actions ─────────────────────────────────────────────────────

    def action_nav_up(self) -> None:
        focusable = self._focusable_indices()
        if focusable:
            self._refresh_cursor(self._cursor - 1)

    def action_nav_down(self) -> None:
        focusable = self._focusable_indices()
        if focusable:
            self._refresh_cursor(self._cursor + 1)

    def action_toggle_item(self) -> None:
        item = self._current_item()
        if item and item.status not in ("done", "active"):
            item.selected = not item.selected
            self._update_ui()

    def action_select_all(self) -> None:
        self._set_section_selection(True)

    def action_select_none(self) -> None:
        self._set_section_selection(False)

    def _set_section_selection(self, selected: bool) -> None:
        """[a]/[n] are scoped to the highlighted item's section *and* its source
        subdirectory: under Images, [a] selects only images, and if the cursor is
        on an item inside input/images/foo/ it selects only the items in foo/ —
        never a sibling subdirectory, never video/audio. When images live flat in
        one directory this naturally means "all images". No-op when the cursor
        isn't on a focusable item (e.g. every section fully done)."""
        current = self._current_item()
        if current is None:
            return
        mtype = current.media_type
        subdir = current.path.parent
        for item in self._items:
            if (item.media_type == mtype
                    and item.path.parent == subdir
                    and item.status not in ("done", "active")):
                item.selected = selected
        self._update_ui()

    def action_invert_sel(self) -> None:
        for item in self._items:
            if item.status not in ("done", "active"):
                item.selected = not item.selected
        self._update_ui()

    def action_retry_failed(self) -> None:
        for item in self._items:
            if item.status == "failed":
                item.status = "queued"
                item.error_msg = ""
                item.pct = 0
        self._update_ui()

    def action_force_redo(self) -> None:
        item = self._current_item()
        if item and item.status == "done":
            item.status = "queued"
            item.done_mtime = ""
            item.selected = True
            self._update_ui()

    def action_reset(self) -> None:
        """Reset everything for a clean re-run: wipe each item's on-disk output
        (the upscaled file plus its progress/audit sidecars), then re-queue and
        select every item so the next [s] regenerates the whole batch from
        scratch. Only files belonging to scanned input items are removed, so
        unrelated output (e.g. the test suite's output/images/test-results/) is
        left intact. A live job is skipped — it is not safe to yank a running
        item's files out from under it."""
        wiped = 0
        for item in self._items:
            if item.status == "active":
                continue
            for art in output_artifacts(item):
                if not art.exists():
                    continue
                try:
                    art.unlink()
                    wiped += 1
                except OSError as exc:
                    self._log(f"reset: could not remove {art.name}: {exc}")
            item.status = "queued"
            item.pct = 0
            item.done_mtime = ""
            item.error_msg = ""
            item.eta_str = ""
            item.throughput_str = ""
            item.selected = True
        self._log(
            f"[bold]Reset[/bold] — wiped {wiped} output file(s); "
            "re-queued all items, press [s] to re-run"
        )
        self._update_ui()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        btn_id = event.button.id or ""
        if btn_id.startswith("sel-"):
            mtype = btn_id[4:]
            for item in self._items:
                if item.media_type == mtype and item.status not in ("done", "active"):
                    item.selected = True
        elif btn_id.startswith("unsel-"):
            mtype = btn_id[6:]
            for item in self._items:
                if item.media_type == mtype and item.status not in ("done", "active"):
                    item.selected = False
        self._update_ui()

    # ── Job control ───────────────────────────────────────────────────────────

    def action_start_batch(self) -> None:
        if self._active_item is not None:
            return
        queue = [i for i in self._items if i.selected and i.status == "queued"]
        if not queue:
            self._log("Nothing queued — select items then press [s]")
            return
        self._run_start = time.time()
        self._run_output_dirs = set()
        self._run_next(queue)

    def _run_next(self, queue: list[MediaItem]) -> None:
        if not queue:
            self._active_item = None
            self._job_start = None
            self.query_one(ActiveJobPanel).set_idle()
            self._update_ui()
            self._log("[bold green]Batch complete[/bold green]")
            self._open_output_dirs()
            return
        item = queue[0]
        remaining = queue[1:]
        item.status = "active"
        item.pct = 0
        self._active_item = item
        self.query_one(ActiveJobPanel).update_job(item)
        self._update_ui()
        self._start_job(item, remaining)

    @work(exclusive=True, thread=False)
    async def _start_job(self, item: MediaItem, remaining: list[MediaItem]) -> None:
        cmd = self._build_cmd(item)
        if cmd is None:
            item.status = "failed"
            item.error_msg = "script not found"
            self._active_item = None
            self._run_next(remaining)
            return

        self._log(f"→ {item.path.name}  [{item.media_type}  {self._preset}]")
        job_start = time.time()
        self._job_start = job_start
        total_files = 1

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            preexec_fn=os.setsid,
        )
        self._job_proc = proc

        async def drain(stream: asyncio.StreamReader) -> None:
            pending = ""
            while True:
                chunk = await stream.read(4096)
                if not chunk:
                    break
                pending += chunk.decode(errors="replace")
                segments, pending = split_progress_stream(pending)
                for seg, is_log in segments:
                    self._handle_progress_line(seg, item, total_files)
                    if is_log:  # \r progress redraws update the bar but don't spam the log
                        self._log(seg)
            tail = pending.strip()
            if tail:
                self._handle_progress_line(tail, item, total_files)
                self._log(tail)

        await asyncio.gather(drain(proc.stdout), drain(proc.stderr))
        rc = await proc.wait()
        self._job_proc = None

        if rc == 0:
            item.status = "done"
            item.done_mtime = datetime.now().strftime("%Y-%m-%d %H:%M")
            item.pct = 100
            self._run_output_dirs.add(self._section_output_root(item.media_type))
            self._log(f"[green]✓ {item.path.name} done[/green]")
        else:
            item.status = "failed"
            item.error_msg = f"exit {rc}"
            self._log(f"[red]✗ {item.path.name} failed (exit {rc})[/red]")

        self._active_item = None
        self._after_job(item, remaining, job_start)

    def _after_job(
        self, item: MediaItem, remaining: list[MediaItem], job_start: float = 0.0
    ) -> None:
        if item.status == "done" and job_start > 0:
            actual_s = time.time() - job_start
            if actual_s > 0:
                item.record_rate(1.0 / actual_s)
                secs = self._actual_secs.setdefault(item.media_type, [])
                secs.append(actual_s)
                avg_s = sum(secs) / len(secs)
                for q in remaining:
                    if q.media_type == item.media_type and q.status == "queued":
                        q.est_seconds = avg_s
        self._update_ui()
        self._run_next(remaining)

    def _build_cmd(self, item: MediaItem) -> list[str] | None:
        o = self._opts
        if item.media_type == "image":
            if not SCRIPT_IMAGE.exists():
                return None
            cmd = ["bash", str(SCRIPT_IMAGE), "-q", self._preset,
                   str(item.path), str(item.output_path.parent)]
            if o["img_scale"]:   cmd += ["-s", o["img_scale"]]
            if o["img_model"]:   cmd += ["-m", o["img_model"]]
            if o["img_format"]:  cmd += ["-f", o["img_format"]]
            if o["img_tile"]:    cmd += ["-t", o["img_tile"]]
            if o["img_face"] == "1": cmd += ["-F"]
            return cmd
        if not SCRIPT_VIDEO.exists():
            return None
        cmd = ["bash", str(SCRIPT_VIDEO), "-q", self._preset,
               str(item.path), str(item.output_path)]
        if o["vid_scale"]:                   cmd += ["-s", o["vid_scale"]]
        if o["vid_engine"]:                  cmd += ["-e", o["vid_engine"]]
        if o.get("vid_dedup") == "1":        cmd += ["-D"]
        if o.get("vid_interpolate"):         cmd += ["-I", o["vid_interpolate"]]
        if o.get("vid_thermal"):             cmd += ["-T", o["vid_thermal"]]
        return cmd

    def _handle_progress_line(
        self, line: str, item: MediaItem, total_files: int
    ) -> None:
        if item.media_type == "image":
            prog = parse_image_progress(line, total_files)
        else:
            prog = parse_video_progress(line)
        if prog is None:
            return
        if prog.get("pct") is not None:
            item.pct = prog["pct"]
        if prog.get("throughput"):
            item.throughput_str = prog["throughput"]
        if prog.get("eta"):
            item.eta_str = prog["eta"]
        self._refresh_active_panel(item)

    def _refresh_active_panel(self, item: MediaItem) -> None:
        elapsed = time.time() - self._job_start if self._job_start else 0.0
        self.query_one(ActiveJobPanel).update_job(item, elapsed)
        self._update_eta()
        self._update_section_counts()

    def action_pause_resume(self) -> None:
        if self._job_proc is None:
            return
        if self._paused:
            os.killpg(os.getpgid(self._job_proc.pid), signal.SIGCONT)
            self._paused = False
            self._log("▶ resumed")
        else:
            os.killpg(os.getpgid(self._job_proc.pid), signal.SIGSTOP)
            self._paused = True
            self._log("⏸ paused")

    def action_cancel_job(self) -> None:
        if self._job_proc is None:
            return
        try:
            os.killpg(os.getpgid(self._job_proc.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass
        if self._active_item:
            self._active_item.status = "queued"
            self._active_item.pct = 0
            self._active_item.throughput_str = ""
            self._active_item.eta_str = ""
        self._log("✖ job cancelled")
        self._update_ui()

    def action_request_quit(self) -> None:
        if self._active_item is not None:
            self._log("[yellow]Job is active — cancel it first [c], then quit [q][/yellow]")
            return
        self.exit()

    # ── Misc ──────────────────────────────────────────────────────────────────

    def _update_header(self) -> None:
        active_opts = [k for k, v in self._opts.items() if v and v != "0"]
        ovr = f"   Overrides [{len(active_opts)} set ●]" if active_opts else ""
        self.query_one("#header-bar", Static).update(
            f"Preset [{self._preset} ▾]   Input [{self._input_dir} ▶]{ovr}",
        )

    def action_cycle_preset(self) -> None:
        # NOTE: a PresetModal picker was attempted but hit a Textual 8.2.7 render
        # quirk ('str' object has no attribute 'render_strips') on a later render.
        # Reverted to cycle until that's resolved — see readme.md TODO.
        if self._active_item is not None:
            self._log("[yellow]Cannot change preset while a job is active[/yellow]")
            return
        idx = _PRESETS.index(self._preset) if self._preset in _PRESETS else 0
        self._preset = _PRESETS[(idx + 1) % len(_PRESETS)]
        for item in self._items:
            if item.status == "queued":
                item.est_seconds = _ETA_SEEDS[item.media_type].get(self._preset, 120.0)
        self._update_ui()
        self._update_header()
        self._log(f"Preset → {self._preset}  (P to cycle)")

    def action_options(self) -> None:
        def _apply(result: dict[str, str] | None) -> None:
            if result is None:
                return
            self._opts = result
            self._update_header()
            active = [k for k, v in result.items() if v and v != "0"]
            if active:
                self._log(f"Options set: {', '.join(f'{k}={self._opts[k]}' for k in active)}")
            else:
                self._log("Options cleared — using preset defaults")

        self.push_screen(OptionsModal(self._opts), _apply)

    def action_help(self) -> None:
        if isinstance(self.screen, HelpScreen):
            self.pop_screen()
        else:
            self.push_screen(HelpScreen())

    def action_change_dir(self) -> None:
        def _apply(new_path: str | None) -> None:
            if not new_path:
                return
            p = Path(new_path).expanduser().resolve()
            if not p.is_dir():
                self._log(f"[red]Not a directory: {p}[/red]")
                return
            self._input_dir = p
            self._items = scan_all(self._preset, self._input_dir, self._output_dir)
            for row in self.query(ChecklistRow):
                row.remove()
            self._populate_rows()
            self._refresh_cursor(0)
            self._update_ui()
            self._update_header()
            self._log(f"Re-scanned {self._input_dir}")

        self.push_screen(DirPrompt(), _apply)

    def _log(self, text: str) -> None:
        try:
            ts = datetime.now().strftime("%H:%M:%S")
            self.query_one(RichLog).write(f"[dim]{ts}[/dim]  {text}")
        except Exception:
            pass


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="media-restore v2 TUI")
    parser.add_argument("--input", type=Path, default=INPUT_DIR, metavar="DIR")
    parser.add_argument("-q", "--preset", default="medium",
                        choices=["low", "medium", "high", "xhigh"])
    args = parser.parse_args()
    MediaRestoreApp(input_dir=args.input, preset=args.preset).run()


if __name__ == "__main__":
    main()
