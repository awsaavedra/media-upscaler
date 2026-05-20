# Video Upscaling — Implementation Plan

## Tool: Video2X

### Why Video2X
- README primary video recommendation; end-to-end local workflow
- Wraps Real-ESRGAN (best general model) + Anime4K backends via ncnn
- Pure CLI, no GUI dependency, pipeline-friendly
- Handles frame extraction, upscale, reassembly, audio mux internally — no manual FFmpeg stitching
- Hardware fit: RTX 3050/3060 Ti + 32GB RAM on 11th-gen Intel H-series is within supported target range

Alternatives considered and rejected:
- Real-ESRGAN + FFmpeg manual pipeline: more steps, more failure surface, better for scripting internals we own
- Anime4K: only for anime/stylized content; not general purpose

---

## Pre-Mortem Risks (diagnostic/pre-mortem)

| Risk | Signal | Prevention |
|---|---|---|
| CUDA driver version mismatch with ncnn backend | `video2x` segfaults or reports no GPU | Run `nvidia-smi` before install; pin driver ≥ 525 |
| Temp storage exhaustion on long encodes | Disk full mid-job, corrupt output | Check `df -h`; require ≥ 50 GB free on SSD; set `--output` to SSD path |
| Audio desync after reassembly | Audio drifts on variable-frame-rate input | Always pass `--vfr` flag on VFR sources; verify with `ffprobe` first |
| Video2X release instability | Binary segfaults on specific codec | Pin to tested release tag; test on 30-second clip before full encode |
| Frame rate loss | Output fps differs from source | Extract and explicitly pass fps via `--fps`; validate with `ffprobe` post-encode |
| Long encode with no progress feedback | Appears hung | Use `--log-level debug` on first run; monitor GPU with `nvidia-smi dmon` |

---

## Prerequisites

### System check commands

```bash
# Verify NVIDIA driver
nvidia-smi

# Verify CUDA availability
nvcc --version || nvidia-smi | grep "CUDA Version"

# Verify FFmpeg (used internally by Video2X)
ffmpeg -version | head -1

# Check available disk
df -h /tmp && df -h ~
```

### Install FFmpeg if missing

```bash
sudo apt update && sudo apt install -y ffmpeg
```

### NVIDIA driver (if not present)

```bash
# Ubuntu 22.04+
sudo apt install -y nvidia-driver-535 nvidia-utils-535
sudo reboot
```

---

## Install Video2X

Video2X provides static binary releases for Linux. Install steps:

```bash
# 1. Create local install directory
mkdir -p ~/.local/bin ~/.local/share/video2x

# 2. Fetch latest release from https://github.com/k4yt3x/video2x/releases
#    Download: video2x-linux-amd64.tar.gz (or the current Linux tarball name)
#    Place in ~/.local/share/video2x/

# 3. Extract
cd ~/.local/share/video2x
tar -xzf video2x-linux-amd64.tar.gz

# 4. Symlink binary onto PATH
ln -sf ~/.local/share/video2x/video2x ~/.local/bin/video2x

# 5. Verify
video2x --version
```

> Release page: https://github.com/k4yt3x/video2x/releases
> Confirm the tarball filename matches the latest release before running step 3.

---

## Wrapper Script: upscale-video.sh

Implements CLI/DevEx rules: POSIX flags, stdin/stdout clean, composable, exit codes as contracts.

### Design

```
upscale-video.sh [OPTIONS] INPUT OUTPUT

Options:
  -s SCALE     Integer upscale factor (default: 2)
  -e ENGINE    realesrgan | anime4k (default: realesrgan)
  -j           Output JSON summary on completion
  -n           Dry run: print command, do not execute
  -h           Help
```

### Validation gates (fail-fast)

1. INPUT exists and is a video file (ffprobe check)
2. OUTPUT directory is writable
3. `video2x` binary is on PATH
4. `nvidia-smi` returns exit 0 (GPU accessible)
5. ≥ 10 GB free on OUTPUT's filesystem (warn if < 50 GB)

### Script skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail

SCALE=2
ENGINE=realesrgan
DRY_RUN=0
JSON_OUT=0

usage() {
  printf 'Usage: %s [-s SCALE] [-e ENGINE] [-j] [-n] INPUT OUTPUT\n' "$0"
  printf '  -s  upscale factor (default: 2)\n'
  printf '  -e  engine: realesrgan | anime4k (default: realesrgan)\n'
  printf '  -j  json summary output\n'
  printf '  -n  dry run\n'
  exit 0
}

while getopts ':s:e:jnh' opt; do
  case $opt in
    s) SCALE=$OPTARG ;;
    e) ENGINE=$OPTARG ;;
    j) JSON_OUT=1 ;;
    n) DRY_RUN=1 ;;
    h) usage ;;
    *) printf 'Unknown flag: -%s\n' "$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

INPUT=${1:?INPUT required}
OUTPUT=${2:?OUTPUT required}

# Boundary validation
command -v video2x >/dev/null 2>&1 || { printf 'video2x not found on PATH\n' >&2; exit 2; }
command -v ffprobe >/dev/null 2>&1 || { printf 'ffprobe not found on PATH\n' >&2; exit 2; }
nvidia-smi >/dev/null 2>&1        || { printf 'GPU not accessible (nvidia-smi failed)\n' >&2; exit 2; }
[ -f "$INPUT" ]                   || { printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2; }
ffprobe -v error "$INPUT" >/dev/null 2>&1 || { printf 'INPUT is not a valid video: %s\n' "$INPUT" >&2; exit 2; }

OUTDIR=$(dirname "$OUTPUT")
[ -w "$OUTDIR" ] || { printf 'OUTPUT directory not writable: %s\n' "$OUTDIR" >&2; exit 2; }

FREE_KB=$(df -k "$OUTDIR" | awk 'NR==2{print $4}')
[ "$FREE_KB" -ge 10485760 ] || printf 'WARNING: < 10 GB free in %s\n' "$OUTDIR" >&2

CMD="video2x -i \"$INPUT\" -o \"$OUTPUT\" -p $ENGINE -s $SCALE"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$CMD"
  exit 0
fi

eval "$CMD"

if [ "$JSON_OUT" -eq 1 ]; then
  printf '{"input":"%s","output":"%s","engine":"%s","scale":%s}\n' \
    "$INPUT" "$OUTPUT" "$ENGINE" "$SCALE"
fi
```

### File location

```
data-restoration-vid-img-aud/
  scripts/
    upscale-video.sh     ← wrapper
  vid-implementation.md  ← this file
```

---

## Test Plan (debug skill — Phase 1 before any fix)

### Smoke test (run first, always)

```bash
# 30-second clip, 2x, realesrgan
./scripts/upscale-video.sh -n test-clip.mp4 /tmp/out.mp4      # dry run — prints command
./scripts/upscale-video.sh test-clip.mp4 /tmp/out.mp4          # real run
ffprobe /tmp/out.mp4                                            # verify output is valid video
```

### Validation checklist

- [ ] `ffprobe` reports output resolution = 2× input resolution
- [ ] Audio present and duration matches source (within 0.1s)
- [ ] No GPU OOM errors in video2x log
- [ ] Output file size > 0 bytes
- [ ] `upscale-video.sh` exits 0 on success, non-zero on each error path

### Error path tests

```bash
upscale-video.sh missing.mp4 /tmp/out.mp4     # expect exit 2
upscale-video.sh test.mp4 /no-write/out.mp4   # expect exit 2
upscale-video.sh -s abc test.mp4 /tmp/out.mp4 # expect exit 1 or video2x error
```

---

## Code Review Gates (code-review skill)

Before merging the wrapper script:

- [ ] No infrastructure imports at logic layer (script has no hardcoded paths outside `$HOME/.local`)
- [ ] All external dependencies validated at boundary (video2x, ffprobe, nvidia-smi checks at top)
- [ ] No magic numbers (scale default named via variable)
- [ ] SRP: script does one thing — validate inputs, delegate to video2x
- [ ] POSIX-compliant flags (`-s`, `-e`, `-j`, `-n`, `-h`)
- [ ] Exit codes: 0 = success, 1 = bad args, 2 = missing dependency/file
- [ ] No interactive prompts; stderr for errors, stdout for output/JSON

---

## Implementation Sequence

1. [ ] Run prerequisite checks (`nvidia-smi`, `ffmpeg -version`)
2. [ ] Download and install Video2X binary from releases page
3. [ ] Run `video2x --version` to confirm install
4. [ ] Create `scripts/upscale-video.sh` from skeleton above
5. [ ] `chmod +x scripts/upscale-video.sh`
6. [ ] Acquire 30-second test clip
7. [ ] Run smoke test
8. [ ] Validate output with ffprobe
9. [ ] Run error path tests
10. [ ] Sign off on code review gates

---

## Decision Log (diagnostic/decision-journal)

| Date | Decision | Rationale | Expected outcome | Confidence | Check-in |
|---|---|---|---|---|---|
| 2026-05-20 | Video2X over manual Real-ESRGAN+FFmpeg | End-to-end, fewer failure points, README primary recommendation | Working CLI pipeline with <30 min setup | 80% | After first real encode |
| 2026-05-20 | Real-ESRGAN engine default (not Anime4K) | General video, not anime | Best quality on live-action footage | 85% | After test clip comparison |
