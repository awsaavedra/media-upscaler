#!/usr/bin/env python3
"""
Upscaling throughput estimator.

Uses measured baselines on the current machine and GPU spec ratios to project
expected fps and encode time on a target hardware profile.

Usage:
  python3 scripts/perf-estimate.py
  python3 scripts/perf-estimate.py --video input/video/clip.mp4
  python3 scripts/perf-estimate.py --video input/video/clip.mp4 --target radeon-8060s
"""

import argparse
import math
import subprocess
import sys

try:
    from rich.console import Console
    from rich.table import Table
    from rich import box
    _RICH = True
except ImportError:
    _RICH = False

# ---------------------------------------------------------------------------
# Measured baselines — RTX 3050 Mobile, this machine
# Each entry: (preset, input_res_label, width, height, fps_measured)
BASELINES = [
    ("medium", "320×180",  320,  180, 2.24),   # RealCUGAN 2×, test-clip
    ("medium", "640×480",  640,  480, 0.61),   # RealCUGAN 2×, sf-market-street
]

# ---------------------------------------------------------------------------
# Hardware profiles
# fp16_tflops: FP16 shader throughput (TFLOPS)
# mem_bw_gbs:  memory bandwidth (GB/s)
# vram_gb:     usable VRAM (GPU-side; unified = full pool)
# notes:       human-readable detail
HARDWARE = {
    "rtx-3050-mobile": {
        "label":       "RTX 3050 Mobile (current)",
        "fp16_tflops": 17.2,   # 2048 cores × 2.1 GHz × 2 FMA × 2 (fp16)
        "mem_bw_gbs":  112.0,  # GDDR6
        "vram_gb":     4.0,
        "gpu_count":   1,
        "notes":       "Measured baseline — 0.61 fps at 640×480 medium",
    },
    "radeon-8060s": {
        "label":       "Radeon 8060S iGPU — 128 GB / 96 GB VRAM (Linux)",
        "fp16_tflops": 29.6,   # 40 CU × 64 sh × 2 × 2.89 GHz × 2 (fp16)
        "mem_bw_gbs":  256.0,  # 256-bit LPDDR5X-8000
        "vram_gb":     96.0,   # Linux override
        "gpu_count":   1,
        "notes":       "AMD Ryzen AI Max+ 395 Strix Halo, 128 GB config",
    },
    "rtx-5090": {
        "label":       "RTX 5090 (single GPU)",
        "fp16_tflops": 419.2,  # 21760 cores × 2407 MHz × 2 FMA × 2 (fp16 shader)
        "mem_bw_gbs":  1792.0, # GDDR7
        "vram_gb":     32.0,
        "gpu_count":   1,
        "notes":       "Blackwell GB202; NCNN uses shader FP16, not Tensor cores",
    },
    "tinybox-green": {
        "label":       "tinybox green v2 — 4× RTX 5090",
        "fp16_tflops": 419.2,  # per GPU — single encode uses one GPU
        "mem_bw_gbs":  1792.0, # per GPU
        "vram_gb":     32.0,   # per GPU
        "gpu_count":   4,      # 4 GPUs → 4 parallel encodes
        "notes":       "tinycorp.myshopify.com — 32-core AMD EPYC Genoa, 192 GB RAM, 4 TB RAID",
    },
}

BASELINE_HW = "rtx-3050-mobile"


def tile_speedup(vram_target_gb: float, vram_base_gb: float) -> float:
    """
    Estimate relative speedup from having more VRAM.
    Large VRAM eliminates tile boundary overhead and allows larger effective
    batch sizes. Modelled as a log-sigmoid capped at 1.4×.
    """
    ratio = vram_target_gb / vram_base_gb
    # log growth: 1.0 at ratio=1, ~1.3 at ratio=24 (96/4)
    benefit = 1.0 + 0.15 * math.log2(ratio)
    return min(benefit, 1.4)


def project_fps(
    baseline_fps: float,
    hw_base: dict,
    hw_target: dict,
) -> float:
    """
    Project fps on target hardware from a measured baseline.

    Model: geometric mean of compute and bandwidth ratios, multiplied by
    a VRAM tile-overhead benefit. Geometric mean reflects that real inference
    is neither purely compute- nor purely bandwidth-bound.
    """
    compute_ratio = hw_target["fp16_tflops"] / hw_base["fp16_tflops"]
    bw_ratio      = hw_target["mem_bw_gbs"]  / hw_base["mem_bw_gbs"]
    combined      = math.sqrt(compute_ratio * bw_ratio)
    tile_factor   = tile_speedup(hw_target["vram_gb"], hw_base["vram_gb"])
    return baseline_fps * combined * tile_factor


def fmt_time(seconds: float) -> str:
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s   = divmod(rem, 60)
    if h:
        return f"{h}h {m:02d}m"
    if m:
        return f"{m}m {s:02d}s"
    return f"{s}s"


def video_duration(path: str) -> float | None:
    try:
        out = subprocess.check_output(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", path],
            text=True, stderr=subprocess.DEVNULL,
        )
        return float(out.strip())
    except Exception:
        return None


def video_dims(path: str) -> tuple[int, int] | None:
    try:
        out = subprocess.check_output(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height", "-of", "csv=p=0", path],
            text=True, stderr=subprocess.DEVNULL,
        )
        w, h = out.strip().split(",")
        return int(w), int(h)
    except Exception:
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--video",  metavar="PATH", help="source video to estimate encode time for")
    parser.add_argument("--target", metavar="HW",   default="radeon-8060s",
                        choices=list(HARDWARE.keys()),
                        help="target hardware profile (default: radeon-8060s)")
    parser.add_argument("--list-hw", action="store_true", help="list available hardware profiles")
    args = parser.parse_args()

    if args.list_hw:
        for k, v in HARDWARE.items():
            print(f"  {k:25s}  {v['label']}")
        sys.exit(0)

    hw_base   = HARDWARE[BASELINE_HW]
    hw_target = HARDWARE[args.target]

    # Build projection table
    rows = []
    for preset, res_label, w, h, base_fps in BASELINES:
        proj_fps   = project_fps(base_fps, hw_base, hw_target)
        speedup    = proj_fps / base_fps
        rows.append((preset, res_label, w, h, base_fps, proj_fps, speedup))

    if _RICH:
        console = Console()
        console.print()
        console.print(f"[bold]Hardware comparison[/bold]")
        gpu_count = hw_target.get("gpu_count", 1)
        console.print(f"  Baseline : {hw_base['label']}")
        console.print(f"  Target   : [green]{hw_target['label']}[/green]")
        if hw_target.get("notes"):
            console.print(f"  Notes    : [dim]{hw_target['notes']}[/dim]")
        console.print(f"  Compute  : {hw_base['fp16_tflops']} → {hw_target['fp16_tflops']} TFLOPS FP16/GPU  "
                      f"([cyan]{hw_target['fp16_tflops']/hw_base['fp16_tflops']:.1f}×[/cyan])")
        console.print(f"  Bandwidth: {hw_base['mem_bw_gbs']} → {hw_target['mem_bw_gbs']} GB/s/GPU  "
                      f"([cyan]{hw_target['mem_bw_gbs']/hw_base['mem_bw_gbs']:.1f}×[/cyan])")
        console.print(f"  VRAM     : {hw_base['vram_gb']} GB → {hw_target['vram_gb']} GB/GPU  "
                      f"(tile overhead eliminated)")
        if gpu_count > 1:
            console.print(f"  GPUs     : [yellow]{gpu_count}× — single encode uses 1 GPU; "
                          f"run {gpu_count} parallel encodes for full throughput[/yellow]")
        console.print()

        t = Table(box=box.SIMPLE_HEAVY, show_header=True)
        t.add_column("Preset",    style="bold")
        t.add_column("Input res", justify="right")
        t.add_column("Baseline fps", justify="right")
        t.add_column("Per-GPU fps", justify="right", style="green")
        t.add_column("Speedup", justify="right", style="cyan")
        if gpu_count > 1:
            t.add_column(f"Batch fps ({gpu_count}× GPU)", justify="right", style="yellow")
        for preset, res_label, _, _, base_fps, proj_fps, speedup in rows:
            row = [preset, res_label, f"{base_fps:.2f}", f"{proj_fps:.2f}", f"{speedup:.1f}×"]
            if gpu_count > 1:
                row.append(f"{proj_fps * gpu_count:.1f}")
            t.add_row(*row)
        console.print(t)

        if args.video:
            dur = video_duration(args.video)
            dims = video_dims(args.video)
            if dur and dims:
                vw, vh = dims
                console.print(f"\n[bold]Encode time estimate[/bold]  {args.video}  "
                               f"({vw}×{vh}, {dur:.0f}s)\n")
                t2 = Table(box=box.SIMPLE_HEAVY)
                t2.add_column("Preset")
                t2.add_column("Scale", justify="right")
                t2.add_column("Output res", justify="right")
                t2.add_column("Baseline", justify="right")
                t2.add_column("Per-GPU", justify="right", style="green")
                if gpu_count > 1:
                    t2.add_column(f"Parallel ({gpu_count}× GPU)", justify="right", style="yellow")
                for preset, (scale, model) in [("medium", (2, "RealCUGAN")),
                                                ("high",   (4, "Real-ESRGAN"))]:
                    ref = next((r for r in rows if r[0] == preset), rows[-1])
                    _, _, rw, rh, base_fps, proj_fps, _ = ref
                    pixel_ratio = (rw * rh) / (vw * vh)
                    adj_base = base_fps * pixel_ratio
                    adj_proj = proj_fps * pixel_ratio
                    frames = dur * 25
                    row = [
                        preset,
                        f"{scale}×",
                        f"{vw*scale}×{vh*scale}",
                        fmt_time(frames / adj_base) if adj_base > 0 else "—",
                        f"[green]{fmt_time(frames / adj_proj)}[/green]" if adj_proj > 0 else "—",
                    ]
                    if gpu_count > 1:
                        adj_parallel = adj_proj * gpu_count
                        row.append(f"[yellow]{fmt_time(frames / adj_parallel)}[/yellow]"
                                   if adj_parallel > 0 else "—")
                    t2.add_row(*row)
                console.print(t2)
    else:
        # Plain fallback
        print(f"\nBaseline : {hw_base['label']}")
        print(f"Target   : {hw_target['label']}")
        print(f"Compute  : {hw_target['fp16_tflops']/hw_base['fp16_tflops']:.1f}× | "
              f"BW: {hw_target['mem_bw_gbs']/hw_base['mem_bw_gbs']:.1f}×\n")
        print(f"{'Preset':<10} {'Input':<10} {'Baseline fps':>14} {'Projected fps':>14} {'Speedup':>8}")
        print("-" * 60)
        for preset, res_label, _, _, base_fps, proj_fps, speedup in rows:
            print(f"{preset:<10} {res_label:<10} {base_fps:>14.2f} {proj_fps:>14.2f} {speedup:>7.1f}×")

        if args.video:
            dur = video_duration(args.video)
            dims = video_dims(args.video)
            if dur and dims:
                vw, vh = dims
                print(f"\nEncode time estimate: {args.video} ({vw}×{vh}, {dur:.0f}s)")
                for preset, (scale, _) in [("medium", (2, "")), ("high", (4, ""))]:
                    ref = next((r for r in rows if r[0] == preset), rows[-1])
                    _, _, rw, rh, base_fps, proj_fps, _ = ref
                    pixel_ratio = (rw * rh) / (vw * vh)
                    frames = dur * 25
                    adj_b = base_fps * pixel_ratio
                    adj_p = proj_fps * pixel_ratio
                    print(f"  {preset:<8} {scale}×  baseline: {fmt_time(frames/adj_b)}  "
                          f"projected: {fmt_time(frames/adj_p)}")


if __name__ == "__main__":
    main()
