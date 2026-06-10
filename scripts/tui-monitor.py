#!/usr/bin/env python3
"""
TUI progress monitor for video upscaling.

Reads video2x output from stdin and displays a live Rich terminal UI showing
frame progress, fps, ETA, and GPU stats.

Usage (pipe from upscale-video.sh):
  ./scripts/upscale-video.sh -q medium input.mp4 output.mp4 2>&1 | \
      python3 scripts/tui-monitor.py --frames 750

Usage (pass total frame count via ffprobe):
  FRAMES=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=nb_frames -of csv=p=0 input.mp4)
  ./scripts/upscale-video.sh -q medium input.mp4 output.mp4 2>&1 | \
      python3 scripts/tui-monitor.py --frames "$FRAMES"
"""

import argparse
import re
import subprocess
import sys
import threading
import time

from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.progress import (BarColumn, Progress, SpinnerColumn,
                            TaskProgressColumn, TextColumn, TimeElapsedColumn,
                            TimeRemainingColumn)
from rich.table import Table
from rich import box


def get_gpu_stats() -> dict:
    """Poll nvidia-smi for current GPU utilisation and VRAM usage."""
    try:
        out = subprocess.check_output(
            ["nvidia-smi",
             "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,clocks.sm",
             "--format=csv,noheader,nounits"],
            text=True, stderr=subprocess.DEVNULL, timeout=1,
        )
        parts = [p.strip() for p in out.strip().split(",")]
        return {
            "util":     int(parts[0]),
            "mem_used": int(parts[1]),
            "mem_total": int(parts[2]),
            "temp":     int(parts[3]),
            "clock":    int(parts[4]),
        }
    except Exception:
        return {}


def build_stats_panel(gpu: dict, current_fps: float, elapsed: float) -> Panel:
    t = Table.grid(padding=(0, 2))
    t.add_column(justify="right", style="dim")
    t.add_column()

    if gpu:
        util_bar = "█" * (gpu["util"] // 10) + "░" * (10 - gpu["util"] // 10)
        t.add_row("GPU util", f"[{'green' if gpu['util'] < 80 else 'yellow'}]{util_bar}[/] {gpu['util']}%")
        t.add_row("VRAM",     f"{gpu['mem_used']} / {gpu['mem_total']} MiB")
        t.add_row("Temp",     f"{gpu['temp']} °C")
        t.add_row("SM clock", f"{gpu['clock']} MHz")
    else:
        t.add_row("GPU stats", "[dim]unavailable[/dim]")

    t.add_row("FPS",     f"[cyan]{current_fps:.2f}[/cyan]" if current_fps > 0 else "—")
    t.add_row("Elapsed", f"{int(elapsed // 60):02d}:{int(elapsed % 60):02d}")
    return Panel(t, title="[bold]Stats[/bold]", border_style="dim")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--frames", type=int, default=0,
                        help="total frame count (enables ETA; detected from video2x output if omitted)")
    args = parser.parse_args()

    console = Console(stderr=True)

    progress = Progress(
        SpinnerColumn(),
        TextColumn("[bold cyan]{task.description}"),
        BarColumn(bar_width=40),
        TaskProgressColumn(),
        TextColumn("•"),
        TimeElapsedColumn(),
        TextColumn("ETA"),
        TimeRemainingColumn(),
        console=console,
        transient=False,
    )
    task = progress.add_task("upscaling", total=args.frames or None)

    gpu_stats: dict = {}
    current_fps: float = 0.0
    start_time = time.time()
    log_lines: list[str] = []

    # Background thread to poll GPU stats every 2 s
    _stop = threading.Event()
    def _poll_gpu():
        while not _stop.is_set():
            nonlocal gpu_stats
            gpu_stats = get_gpu_stats()
            _stop.wait(2)
    threading.Thread(target=_poll_gpu, daemon=True).start()

    frame_re = re.compile(
        r'frame=(\d+)/(\d+)\s+\(([^)]+)\);\s*fps=([^;]+);\s*elapsed=([^;]+);\s*remaining=(\S+)'
    )
    info_re = re.compile(r'\[(?:info|warning|error|critical)\]\s+(.*)')

    layout = Layout()
    layout.split_row(
        Layout(name="progress", ratio=3),
        Layout(name="stats",    ratio=1),
    )

    with Live(layout, console=console, refresh_per_second=4, screen=False):
        for raw_line in sys.stdin:
            line = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', raw_line).replace('\r', '').strip()
            if not line:
                continue

            m = frame_re.search(line)
            if m:
                cur, total_str, pct_str, fps_str, elapsed_str, remaining_str = m.groups()
                cur = int(cur)
                total = int(total_str)
                try:
                    current_fps = float(fps_str)
                except ValueError:
                    pass

                if progress.tasks[0].total != total:
                    progress.update(task, total=total)
                progress.update(task, completed=cur,
                                description=f"frame {cur}/{total}  {pct_str}")

            im = info_re.search(line)
            if im:
                msg = im.group(1)[:80]
                log_lines.append(msg)
                log_lines = log_lines[-6:]

            elapsed = time.time() - start_time
            log_text = "\n".join(f"[dim]{l}[/dim]" for l in log_lines) or "[dim]waiting…[/dim]"

            layout["progress"].update(
                Panel(progress, title="[bold]Video upscaling[/bold]",
                      subtitle=log_text, border_style="blue")
            )
            layout["stats"].update(build_stats_panel(gpu_stats, current_fps, elapsed))

    _stop.set()
    elapsed = time.time() - start_time
    final_fps = (progress.tasks[0].completed or 0) / elapsed if elapsed > 0 else 0
    console.print(f"\n[bold green]Done[/bold green]  "
                  f"{int(progress.tasks[0].completed or 0)} frames  "
                  f"{final_fps:.2f} fps avg  "
                  f"elapsed {int(elapsed // 60):02d}:{int(elapsed % 60):02d}")


if __name__ == "__main__":
    main()
