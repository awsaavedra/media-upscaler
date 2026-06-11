#!/usr/bin/env python3
"""media-restore v2 TUI — interactive job queue for image and video upscaling."""
from __future__ import annotations

import asyncio
import json
import os
import re
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
    "image": {"low": 30.0, "medium": 120.0, "high": 120.0, "ultrahigh": 300.0},
    "video": {"low": 10.0, "medium": 1320.0, "high": 5400.0, "ultrahigh": 7200.0},
}

_PRESETS = ["low", "medium", "high", "ultrahigh"]

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
                return f"✓ done     {self.done_mtime}"
            case "active":
                pct = f"▶ active   {self.pct}%"
                eta = f"  {self.eta_str} left" if self.eta_str else ""
                thr = f"  · {self.throughput_str}" if self.throughput_str else ""
                return pct + eta + thr
            case "queued":
                m = max(1, round(self.est_seconds / 60))
                return f"· queued   est. ~{m} m"
            case "failed":
                return f"✗ failed   {self.error_msg}"
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
        if out.exists():
            item.status = "done"
            item.done_mtime = _mtime_str(out)
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
        if out.exists():
            item.status = "done"
            item.done_mtime = _mtime_str(out)
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
    if not queued:
        return f"Elapsed  {_fmt_dur(elapsed)}  ·  Queue complete"
    return (
        f"Elapsed  {_fmt_dur(elapsed)}  ·  "
        f"Total ETA  {_fmt_mins(total_s)} remaining   ({len(queued)} queued)"
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


def render_gpu_text(gpu: dict) -> str:
    if not gpu:
        return "GPU stats unavailable"
    w = 14
    uf = round(gpu["util"] / 100 * w)
    vf = round(gpu["mem_used"] / max(gpu["mem_total"], 1) * w)
    ub = "█" * uf + "░" * (w - uf)
    vb = "█" * vf + "░" * (w - vf)
    gu = gpu["mem_used"] / 1024
    gt = gpu["mem_total"] / 1024
    return (
        f"Util   {ub}  {gpu['util']:3d} %\n"
        f"VRAM   {vb}  {gu:.1f} / {gt:.1f} GB\n"
        f"Temp   {gpu['temp']} °C  ·  Clock  {gpu['clock']} MHz"
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


def parse_video_progress(line: str) -> dict | None:
    clean = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", line).replace("\r", "")
    m = _VID_FRAME_RE.search(clean)
    if not m:
        return None
    cur, tot, fps, _elapsed, remaining = m.groups()
    pct = round(int(cur) / max(int(tot), 1) * 100)
    return {"pct": pct, "throughput": f"{fps.strip()} fps", "eta": remaining.strip()}


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
"""


class ChecklistRow(Widget):
    can_focus = False  # App manages cursor/highlighting manually
    _render_markup = False  # [✓] [✗] [ ] are literal characters, not markup

    def __init__(self, item: MediaItem, idx: int) -> None:
        super().__init__(id=f"row-{idx}")
        self.item = item
        self.idx = idx

    def render(self) -> str:
        name = self.item.path.name
        if len(name) > 30:
            name = name[:28] + "…"
        return f"{self.item.checkbox} {name:<30}  {self.item.status_label}"

    def sync_classes(self) -> None:
        self.remove_class("done", "active", "failed")
        if self.item.status == "done":
            self.add_class("done")
        elif self.item.status == "active":
            self.add_class("active")
        elif self.item.status == "failed":
            self.add_class("failed")
        self.refresh()


_SEC_CSS = """
SectionHeader {
    height: 2;
    background: $panel-darken-2;
    padding: 0 1;
}
.sec-label { width: auto; margin-right: 2; }
.sec-count { width: 1fr; color: $text-muted; }
.sec-btn   { height: 1; min-width: 14; border: none; background: $surface; margin-right: 1; }
"""


class SectionHeader(Horizontal):
    def __init__(self, title: str, media_type: str) -> None:
        super().__init__()
        self._title = title
        self._mtype = media_type

    def compose(self) -> ComposeResult:
        yield Label(f"── {self._title}", classes="sec-label")
        yield Label("", id=f"sec-count-{self._mtype}", classes="sec-count")
        yield Button("select all",   id=f"sel-{self._mtype}",   classes="sec-btn")
        yield Button("unselect all", id=f"unsel-{self._mtype}", classes="sec-btn")

    def update_counts(self, items: list[MediaItem]) -> None:
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

    def update_job(self, item: MediaItem) -> None:
        self.query_one("#job-name", Label).update(item.path.name)
        if item.pct is not None:
            self.query_one("#job-bar", ProgressBar).update(progress=item.pct, total=100)
        detail = item.throughput_str or ""
        if item.eta_str:
            detail = (detail + "  ·  " if detail else "") + f"{item.eta_str} left"
        self.query_one("#job-detail", Label).update(detail or "running…")


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


_KEY_CSS = """
KeyHintsBar {
    height: 2;
    background: $panel-darken-2;
    color: $text-muted;
    padding: 0 1;
}
"""

_ROW1 = "[↑↓] navigate   [SPACE] toggle   [a] all   [n] none   [t] invert   [r] retry failed   [f] force redo"
_ROW2 = "[s] start   [p] pause/resume   [c] cancel job   [P] preset   [d] change dir   [q] quit"


class KeyHintsBar(Static):
    _render_markup = False  # [↑↓] [SPACE] etc. are literal key hint text

    def render(self) -> str:
        return f"{_ROW1}\n{_ROW2}"


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

    BINDINGS = [
        Binding("up",    "nav_up",        show=False),
        Binding("down",  "nav_down",      show=False),
        Binding("space", "toggle_item",   show=False),
        Binding("a",     "select_all",    show=False),
        Binding("n",     "select_none",   show=False),
        Binding("t",     "invert_sel",    show=False),
        Binding("r",     "retry_failed",  show=False),
        Binding("f",     "force_redo",    show=False),
        Binding("s",     "start_batch",   show=False),
        Binding("p",     "pause_resume",  show=False),
        Binding("c",     "cancel_job",    show=False),
        Binding("P",     "cycle_preset",  show=False),
        Binding("q",     "request_quit",  show=False),
    ]

    def __init__(self, input_dir: Path = INPUT_DIR, preset: str = "medium") -> None:
        super().__init__()
        self._input_dir = input_dir
        self._output_dir = OUTPUT_DIR
        self._preset = preset
        self._items: list[MediaItem] = []
        self._cursor: int = 0
        self._run_start: float | None = None
        self._active_item: MediaItem | None = None
        self._job_proc: asyncio.subprocess.Process | None = None
        self._paused = False
        self._gpu: dict = {}
        self._actual_secs: dict[str, list[float]] = {}

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
        self._reattach_sidecars()

    def _populate_rows(self) -> None:
        img_list = self.query_one("#img-list", Vertical)
        vid_list = self.query_one("#vid-list", Vertical)
        for idx, item in enumerate(self._items):
            row = ChecklistRow(item, idx)
            row.sync_classes()
            target = img_list if item.media_type == "image" else vid_list
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
                    item.status = "active"
                    item.pct = int(data.get("pct", 0))
                    changed = True
            except Exception:
                pass
        if changed:
            self._update_ui()

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
                if item.output_path.exists():
                    item.status = "done"
                    item.done_mtime = _mtime_str(item.output_path)
                else:
                    item.status = "queued"
                    item.pct = 0
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
                else:
                    new_pct = int(data.get("pct", item.pct))
                    if new_pct != item.pct:
                        item.pct = new_pct
                        changed = True
                    item.throughput_str = str(data.get("throughput", item.throughput_str))
                    item.eta_str = str(data.get("remaining", item.eta_str))
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
        for item in self._items:
            if item.status not in ("done", "active"):
                item.selected = True
        self._update_ui()

    def action_select_none(self) -> None:
        for item in self._items:
            if item.status not in ("done", "active"):
                item.selected = False
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
        self._run_next(queue)

    def _run_next(self, queue: list[MediaItem]) -> None:
        if not queue:
            self._active_item = None
            self.query_one(ActiveJobPanel).set_idle()
            self._update_ui()
            self._log("[bold green]Batch complete[/bold green]")
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
            self.call_from_thread(self._run_next, remaining)
            return

        self._log(f"→ {item.path.name}  [{item.media_type}  {self._preset}]")
        job_start = time.time()
        total_files = 1

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            preexec_fn=os.setsid,
        )
        self._job_proc = proc

        async def drain(stream: asyncio.StreamReader) -> None:
            async for raw in stream:
                line = raw.decode(errors="replace").rstrip()
                self._handle_progress_line(line, item, total_files)
                self._log(line)

        await asyncio.gather(drain(proc.stdout), drain(proc.stderr))
        rc = await proc.wait()
        self._job_proc = None

        if rc == 0:
            item.status = "done"
            item.done_mtime = datetime.now().strftime("%Y-%m-%d %H:%M")
            item.pct = 100
            self._log(f"[green]✓ {item.path.name} done[/green]")
        else:
            item.status = "failed"
            item.error_msg = f"exit {rc}"
            self._log(f"[red]✗ {item.path.name} failed (exit {rc})[/red]")

        self._active_item = None
        self.call_from_thread(self._after_job, item, remaining, job_start)

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
        if item.media_type == "image":
            if not SCRIPT_IMAGE.exists():
                return None
            return [
                "bash", str(SCRIPT_IMAGE),
                "-q", self._preset,
                str(item.path),
                str(item.output_path.parent),
            ]
        if not SCRIPT_VIDEO.exists():
            return None
        return [
            "bash", str(SCRIPT_VIDEO),
            "-q", self._preset,
            str(item.path),
            str(item.output_path),
        ]

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
        self.call_from_thread(self._refresh_active_panel, item)

    def _refresh_active_panel(self, item: MediaItem) -> None:
        self.query_one(ActiveJobPanel).update_job(item)
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
        self.query_one("#header-bar", Static).update(
            f"Preset [{self._preset} ▾]   Input [{self._input_dir} ▶]",
        )

    def action_cycle_preset(self) -> None:
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
        self._log(f"Preset → {self._preset}")

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
                        choices=["low", "medium", "high", "ultrahigh"])
    args = parser.parse_args()
    MediaRestoreApp(input_dir=args.input, preset=args.preset).run()


if __name__ == "__main__":
    main()
