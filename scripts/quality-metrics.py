#!/usr/bin/env python3
"""Measure upscale quality against a ground-truth reference.

Computes full-reference image-quality metrics between an upscaled OUTPUT and a
ground-truth GT image:

  - PSNR (peak signal-to-noise ratio, dB)  — fidelity; higher is better
  - SSIM (structural similarity, 0..1)     — structure; higher is better
  - LPIPS (learned perceptual distance)    — perceptual; LOWER is better (optional)

PSNR/SSIM reward pixel fidelity and penalise the perceptual sharpening that GAN
upscalers (Real-ESRGAN) deliberately introduce, so a low PSNR is not by itself a
quality failure for those models. LPIPS is the fairer perceptual score; enable it
with --lpips (requires the `lpips` package: `pip install lpips`).

When OUTPUT and GT differ in size (non-integer effective scale), OUTPUT is
resized to GT dimensions with Lanczos and the result is flagged informational —
pass --strict-size to require an exact match instead.

Exit codes: 0 = measured (and thresholds met, if given); 1 = a --min threshold
was not met; 2 = usage / IO error.
"""

import argparse
import json
import sys

import cv2
import numpy as np
from PIL import Image
from skimage.metrics import peak_signal_noise_ratio, structural_similarity


def load_rgb(path):
    """Load an image as an HxWx3 uint8 RGB array."""
    try:
        return np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)
    except (FileNotFoundError, OSError) as exc:
        die(f"cannot read image {path!r}: {exc}")


def resize_to(image, height, width):
    """Resize image to (height, width) with Lanczos resampling."""
    return cv2.resize(image, (width, height), interpolation=cv2.INTER_LANCZOS4)


def compute_psnr(gt, output):
    """PSNR in dB; inf when the images are identical."""
    if np.array_equal(gt, output):
        return float("inf")
    return float(peak_signal_noise_ratio(gt, output, data_range=255))


def compute_ssim(gt, output):
    """Mean structural similarity over the three colour channels, 0..1."""
    return float(structural_similarity(gt, output, channel_axis=2, data_range=255))


def compute_lpips(gt, output):
    """Learned perceptual distance (AlexNet backbone); lower is better.

    Returns None if the optional `lpips` package is not installed.
    """
    try:
        import lpips  # optional, heavy (torch); imported lazily
        import torch
    except ImportError:
        return None
    to_tensor = lambda a: (
        torch.from_numpy(a).permute(2, 0, 1).float().div(127.5).sub(1.0).unsqueeze(0)
    )
    model = lpips.LPIPS(net="alex", verbose=False)
    with torch.no_grad():
        distance = model(to_tensor(gt), to_tensor(output))
    return float(distance.item())


def measure(gt_path, output_path, want_lpips, strict_size):
    """Return a metrics dict for one GT/OUTPUT pair."""
    gt = load_rgb(gt_path)
    output = load_rgb(output_path)

    gt_h, gt_w = gt.shape[:2]
    out_h, out_w = output.shape[:2]
    resized = (gt_h, gt_w) != (out_h, out_w)
    if resized:
        if strict_size:
            die(f"size mismatch: GT {gt_w}x{gt_h} vs OUTPUT {out_w}x{out_h} "
                "(omit --strict-size to compare after Lanczos resize)")
        output = resize_to(output, gt_h, gt_w)

    metrics = {
        "gt": gt_path,
        "output": output_path,
        "gt_size": f"{gt_w}x{gt_h}",
        "output_size": f"{out_w}x{out_h}",
        "resized_for_comparison": resized,
        "psnr_db": round(compute_psnr(gt, output), 3),
        "ssim": round(compute_ssim(gt, output), 4),
    }
    if want_lpips:
        lpips_value = compute_lpips(gt, output)
        metrics["lpips"] = None if lpips_value is None else round(lpips_value, 4)
        metrics["lpips_available"] = lpips_value is not None
    return metrics


def check_thresholds(metrics, min_psnr, min_ssim):
    """Return a list of human-readable threshold failures (empty = all met)."""
    failures = []
    if min_psnr is not None and metrics["psnr_db"] < min_psnr:
        failures.append(f"PSNR {metrics['psnr_db']} < {min_psnr} dB")
    if min_ssim is not None and metrics["ssim"] < min_ssim:
        failures.append(f"SSIM {metrics['ssim']} < {min_ssim}")
    return failures


def die(message):
    print(f"quality-metrics: {message}", file=sys.stderr)
    sys.exit(2)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Measure upscale quality (PSNR/SSIM/LPIPS) against ground truth.")
    parser.add_argument("gt", help="ground-truth reference image")
    parser.add_argument("output", help="upscaled image to score")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    parser.add_argument("--lpips", action="store_true",
                        help="also compute LPIPS perceptual distance (needs `lpips`)")
    parser.add_argument("--strict-size", action="store_true",
                        help="require exact size match instead of resizing OUTPUT")
    parser.add_argument("--min-psnr", type=float, metavar="DB",
                        help="exit non-zero if PSNR is below this (dB)")
    parser.add_argument("--min-ssim", type=float, metavar="X",
                        help="exit non-zero if SSIM is below this (0..1)")
    return parser.parse_args(argv)


def format_human(metrics, failures):
    lines = [f"{metrics['output']}  vs  {metrics['gt']}"]
    note = "  (resized to GT — informational)" if metrics["resized_for_comparison"] else ""
    lines.append(f"  size      {metrics['output_size']} → {metrics['gt_size']}{note}")
    lines.append(f"  PSNR      {metrics['psnr_db']} dB")
    lines.append(f"  SSIM      {metrics['ssim']}")
    if "lpips" in metrics:
        value = metrics["lpips"] if metrics["lpips_available"] else "n/a (pip install lpips)"
        lines.append(f"  LPIPS     {value}")
    if failures:
        lines.append("  FAIL      " + "; ".join(failures))
    return "\n".join(lines)


def main(argv):
    args = parse_args(argv)
    metrics = measure(args.gt, args.output, args.lpips, args.strict_size)
    failures = check_thresholds(metrics, args.min_psnr, args.min_ssim)
    if args.json:
        metrics["passed"] = not failures
        metrics["failures"] = failures
        print(json.dumps(metrics))
    else:
        print(format_human(metrics, failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
