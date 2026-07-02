---
name: Bug report
about: A reproducible defect in the upscaling pipeline or TUI
title: "[bug] "
labels: bug
---

## What happened
<!-- Clear description of the defect and the actual result. -->

## Command or action
<!-- Exact command or TUI action, e.g. ./scripts/upscale-video.sh -q high in.mp4 out.mp4 -->

## Expected result

## Media
- Type: image / video / audio
- Source (approx size, resolution, codec):

## Environment
- OS / distro:
- GPU + driver (first line of `nvidia-smi`):
- `./scripts/check-gpu.sh` output:
- Commit or tag:

## Exit code
<!-- 0 = success · 1 = validation · 2 = dependency/setup · 3 = inference (see CONTRIBUTING.md) -->

## Logs
<!-- Relevant output. Re-running with -j (JSON) or attaching the .audit.json manifest helps. -->
