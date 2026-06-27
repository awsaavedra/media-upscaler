#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Prefer local install; allow override via env var or PATH fallback
if [ -z "${VIDEO2X:-}" ]; then
  if [ -f "$PROJECT_ROOT/tools/video2x/video2x" ]; then
    VIDEO2X="$PROJECT_ROOT/tools/video2x/video2x"
  elif command -v video2x >/dev/null 2>&1; then
    VIDEO2X=video2x
  fi
fi

QUALITY=""        # unset = medium; fast|low|medium|high|xhigh
SCALE=""          # unset = resolved from quality preset
ENGINE=""         # unset = resolved from quality preset
NVENC=0           # 1 = re-encode via system ffmpeg h264_nvenc after AI upscale (xhigh)
DEDUP=0           # 1 = pre-filter with mpdecimate to skip duplicate frames
INTERPOLATE=""    # "2x" = double framerate via RIFE (or ffmpeg minterpolate fallback)
THERMAL_MODE="balanced"  # conservative|balanced|performance
DRY_RUN=0
JSON_OUT=0
CALIBRATE=0       # -c: run 30-frame probe before full job; prints measured fps + ETA
CHUNK_SECS=0      # -C N: segment into N-second chunks for resume; 0 = no chunking (default)
RESUME=0          # -r: skip already-upscaled chunks; requires -C to have been used before

usage() {
  printf 'Usage: %s [-q QUALITY] [-s SCALE] [-e ENGINE] [-C SECS] [-r] [-c] [-j] [-n] INPUT OUTPUT\n' "$0"
  printf '\n'
  printf '  -q  quality preset — sets scale and engine together (default: medium)\n'
  printf '        fast      realesr-animevideov3 2x  Vulkan    ≥9 fps @320×180  speed focus\n'
  printf '        low       ffmpeg lanczos 2x         CPU       ~seconds/clip    no GPU\n'
  printf '        medium    RealCUGAN 2x              Vulkan    ~45 min/30 s    recommended\n'
  printf '        high      Real-ESRGAN 4x            Vulkan    ~2 h/30 s       best quality\n'
  printf '        xhigh Real-ESRGAN 4x            NVENC out ~2 h/30 s       max quality\n'
  printf '\n'
  printf '  -s  override scale factor integer (overrides the -q scale)\n'
  printf '  -e  override engine: realesrgan | realcugan | anime4k (overrides the -q engine)\n'
  printf '  -D  enable duplicate-frame skip (mpdecimate filter before inference)\n'
  printf '  -I  frame interpolation factor: 2x (doubles framerate; RIFE or minterpolate)\n'
  printf '  -T  thermal mode: conservative | balanced (default) | performance\n'
  printf '  -C  chunk duration in seconds for crash-safe processing (default: 0 = no chunking)\n'
  printf '        chunks land in OUTPUT.chunks/; concat on completion; resume with -r\n'
  printf '  -r  resume: skip chunks whose upscaled output already exists in OUTPUT.chunks/\n'
  printf '  -c  calibration probe: upscale 30 frames, print measured fps + ETA before full run\n'
  printf '  -j  print json summary to stdout on completion\n'
  printf '  -n  dry run: print command, do not execute\n'
  printf '  -h  help\n'
  exit 0
}

while getopts ':q:s:e:C:I:T:rcDjnh' opt; do
  case $opt in
    q) QUALITY=$OPTARG ;;
    s) SCALE=$OPTARG ;;
    e) ENGINE=$OPTARG ;;
    C) CHUNK_SECS=$OPTARG ;;
    r) RESUME=1 ;;
    c) CALIBRATE=1 ;;
    D) DEDUP=1 ;;
    I) INTERPOLATE=$OPTARG ;;
    T) THERMAL_MODE=$OPTARG ;;
    j) JSON_OUT=1 ;;
    n) DRY_RUN=1 ;;
    h) usage ;;
    :) printf 'Flag -%s requires an argument\n' "$OPTARG" >&2; exit 1 ;;
    *) printf 'Unknown flag: -%s\n' "$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

INPUT=${1:?'INPUT required — path to source video'}
OUTPUT=${2:?'OUTPUT required — path for upscaled video'}

# Validate quality
case ${QUALITY:-medium} in
  fast|low|medium|high|xhigh) ;;
  *) printf 'QUALITY must be fast, low, medium, high, or xhigh, got: %s\n' "$QUALITY" >&2; exit 1 ;;
esac

# Validate thermal mode
case $THERMAL_MODE in
  conservative|balanced|performance) ;;
  *) printf 'THERMAL_MODE must be conservative, balanced, or performance, got: %s\n' "$THERMAL_MODE" >&2; exit 1 ;;
esac

# Validate interpolation factor
case ${INTERPOLATE:-none} in
  none|2x) ;;
  *) printf 'INTERPOLATE must be 2x, got: %s\n' "$INTERPOLATE" >&2; exit 1 ;;
esac

# Apply quality preset; explicit -s / -e override the preset values
# xhigh uses realesrgan 4× AI upscale then NVENC re-encode via system ffmpeg
case ${QUALITY:-medium} in
  fast)      SCALE=${SCALE:-2}; ENGINE=${ENGINE:-realesrgan_video} ;;
  low)       SCALE=${SCALE:-2}; ENGINE=${ENGINE:-ffmpeg_scale} ;;
  medium)    SCALE=${SCALE:-2}; ENGINE=${ENGINE:-realcugan} ;;
  high)      SCALE=${SCALE:-4}; ENGINE=${ENGINE:-realesrgan} ;;
  xhigh) SCALE=${SCALE:-4}; ENGINE=${ENGINE:-realesrgan}; NVENC=1 ;;
esac

# Validate scale
case $SCALE in
  ''|*[!0-9]*) printf 'SCALE must be a positive integer, got: %s\n' "$SCALE" >&2; exit 1 ;;
esac

# Validate engine (ffmpeg_scale/realesrgan_video are internal; set by -q presets, not -e)
case $ENGINE in
  realesrgan|realcugan|anime4k|ffmpeg_scale|realesrgan_video) ;;
  tensorrt)
    # TensorRT requires PyTorch + CUDA — check for deps and fail with install guidance
    if ! python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
      printf 'tensorrt engine requires PyTorch with CUDA support.\n' >&2
      printf '  Install: pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121\n' >&2
      printf '  Then verify: python3 -c "import torch; print(torch.cuda.is_available())"\n' >&2
      exit 2
    fi
    printf '[tensorrt] PyTorch CUDA available — TensorRT FP16 path not yet implemented; using realesrgan\n' >&2
    ENGINE=realesrgan
    ;;
  *) printf 'ENGINE must be realesrgan, realcugan, anime4k, or tensorrt (or use -q fast/low for preset engines), got: %s\n' "$ENGINE" >&2; exit 1 ;;
esac

# Boundary checks — only require GPU tools when engine needs them
command -v ffprobe >/dev/null 2>&1 || { printf 'ffprobe not found on PATH (install ffmpeg)\n' >&2; exit 2; }

if [ "$ENGINE" = "ffmpeg_scale" ]; then
  command -v ffmpeg >/dev/null 2>&1 || { printf 'ffmpeg not found on PATH\n' >&2; exit 2; }
else
  [ -n "${VIDEO2X:-}" ] && [ -x "$VIDEO2X" ] \
    || { printf 'video2x not found — run scripts/setup.sh or set VIDEO2X env var\n' >&2; exit 2; }
  nvidia-smi >/dev/null 2>&1 || { printf 'GPU not accessible — nvidia-smi failed\n' >&2; exit 2; }
fi

# Batch directory mode: recurse self per video file, mirror tree, skip done, report summary
if [ -d "$INPUT" ]; then
  _PASS=0; _FAIL=0; _SKIP=0
  _ARGS=()
  [ -n "${QUALITY:-}" ] && _ARGS+=(-q "$QUALITY")
  [ -n "${SCALE:-}"   ] && _ARGS+=(-s "$SCALE")
  [ -n "${ENGINE:-}"  ] && _ARGS+=(-e "$ENGINE")
  [ "$CHUNK_SECS" -gt 0 ] && _ARGS+=(-C "$CHUNK_SECS")
  [ "$RESUME"    -eq 1 ] && _ARGS+=(-r)
  [ "$CALIBRATE" -eq 1 ] && _ARGS+=(-c)
  [ "$DEDUP"     -eq 1 ] && _ARGS+=(-D)
  [ -n "${INTERPOLATE:-}" ] && _ARGS+=(-I "$INTERPOLATE")
  [ "$THERMAL_MODE" != "balanced" ] && _ARGS+=(-T "$THERMAL_MODE")
  [ "$JSON_OUT"  -eq 1 ] && _ARGS+=(-j)
  while IFS= read -r _vf; do
    _rel="${_vf#$INPUT}"; _rel="${_rel#/}"
    _ext="${_vf##*.}"
    _stem="${_rel%.*}"
    _vout="$OUTPUT/${_stem}_upscaled.${_ext}"
    if [ -f "$_vout" ]; then
      printf '[skip] %s (output exists)\n' "$_rel" >&2
      _SKIP=$((_SKIP + 1)); continue
    fi
    mkdir -p "$(dirname "$_vout")"
    printf '→ %s\n' "$_rel" >&2
    if "$0" "${_ARGS[@]}" "$_vf" "$_vout"; then
      _PASS=$((_PASS + 1))
    else
      printf '[fail] %s\n' "$_rel" >&2
      _FAIL=$((_FAIL + 1))
    fi
  done < <(find "$INPUT" -type f \
    \( -name '*.mp4' -o -name '*.mkv' -o -name '*.avi' \
       -o -name '*.mov' -o -name '*.webm' -o -name '*.wmv' \
       -o -name '*.flv' -o -name '*.m4v' \) | sort)
  printf '\nDone: %d converted, %d skipped, %d failed\n' "$_PASS" "$_SKIP" "$_FAIL" >&2
  [ "$_FAIL" -eq 0 ] && exit 0 || exit 3
fi

[ -f "$INPUT" ] || { printf 'INPUT not found: %s\n' "$INPUT" >&2; exit 2; }
# Duration must be a numeric value — images report "N/A" and fail this check
_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null)
case $_DUR in
  ''|N/A) printf 'INPUT is not a valid video file: %s\n' "$INPUT" >&2; exit 2 ;;
esac

OUTDIR=$(dirname "$OUTPUT")
mkdir -p "$OUTDIR" 2>/dev/null \
  || { printf 'Cannot create OUTPUT directory: %s\n' "$OUTDIR" >&2; exit 2; }
[ -w "$OUTDIR" ] || { printf 'OUTPUT directory not writable: %s\n' "$OUTDIR" >&2; exit 2; }

# Temp-disk preflight: estimate output size from bitrate × duration × scale²
# Raw uncompressed frames are the peak; lossless intermediate adds ~2× source size.
# Formula: bitrate_kbps × duration_s × scale² / 8 → bytes; add 2× source for temp.
_SRC_KB=$(du -k "$INPUT" 2>/dev/null | awk '{print $1}')
_BIT_KBPS=$(ffprobe -v error -show_entries format=bit_rate -of csv=p=0 "$INPUT" 2>/dev/null \
  | awk '{printf "%d", $1/1000}')
_EST_OUT_KB=$(echo "$_DUR ${_BIT_KBPS:-5000} $SCALE" \
  | awk '{printf "%d", $1 * $2 * $3 * $3 / 8}')
_NEED_KB=$(( (_EST_OUT_KB + _SRC_KB * 2) > 0 ? (_EST_OUT_KB + _SRC_KB * 2) : 10485760 ))
FREE_KB=$(df -k "$OUTDIR" | awk 'NR==2{print $4}')
if [ "$FREE_KB" -lt "$_NEED_KB" ]; then
  printf 'ERROR: need ~%d GB, only %d GB free in %s — aborting\n' \
    "$((_NEED_KB / 1048576))" "$((FREE_KB / 1048576))" "$OUTDIR" >&2
  exit 2
elif [ "$FREE_KB" -lt 52428800 ]; then
  printf 'WARNING: < 50 GB free in %s — large encodes may exhaust disk\n' "$OUTDIR" >&2
fi

# Build command for selected engine
case $ENGINE in
  ffmpeg_scale)
    CMD=(ffmpeg -i "$INPUT"
         -vf "scale=iw*${SCALE}:ih*${SCALE}:flags=lanczos"
         -c:v libx264 -crf 18 -preset fast -c:a copy -y "$OUTPUT")
    ;;
  realesrgan_video)
    # SRVGGNet compact model — native video-optimised, fastest GPU path (~3-4× medium)
    CMD=("$VIDEO2X" -i "$INPUT" -o "$OUTPUT" -s "$SCALE"
         -p realesrgan --realesrgan-model realesr-animevideov3)
    ;;
  realesrgan)
    # realesrgan-plus is the general live-action model; default is anime-optimised
    CMD=("$VIDEO2X" -i "$INPUT" -o "$OUTPUT" -s "$SCALE"
         -p realesrgan --realesrgan-model realesrgan-plus)
    ;;
  realcugan)
    # models-se is the general-purpose variant with 2x/3x/4x support
    CMD=("$VIDEO2X" -i "$INPUT" -o "$OUTPUT" -s "$SCALE"
         -p realcugan --realcugan-model models-se)
    ;;
  anime4k)
    # anime4k is a libplacebo shader in 6.x, not a standalone processor
    CMD=("$VIDEO2X" -i "$INPUT" -o "$OUTPUT" -s "$SCALE"
         -p libplacebo --libplacebo-shader anime4k-v4-a)
    ;;
esac

# Thermal throttling helper — called between major phases
_thermal_sleep() {
  case $THERMAL_MODE in
    conservative)
      # 5 s pause between phases; lets GPU cool slightly before next heavy workload
      sleep 5
      ;;
    balanced|performance) : ;;
  esac
}

if [ "$DRY_RUN" -eq 1 ]; then
  [ "$DEDUP"     -eq 1 ] && printf '# dedup: mpdecimate pre-filter\n'
  [ -n "$INTERPOLATE" ] && printf '# interpolate: %s\n' "$INTERPOLATE"
  [ "$NVENC"     -eq 1 ] && printf '# nvenc: h264_nvenc re-encode after AI upscale\n'
  printf '%s\n' "${CMD[*]}"
  exit 0
fi

# Duplicate-frame skip: pre-filter input with mpdecimate before AI upscale.
# Creates a deduplicated temp clip; CMD is updated to use it as input.
# After upscaling, the original framerate is restored by repeating held frames.
_DEDUP_TMP=""
_DEDUP_ORIG_FRAMES="${_FRAMES:-0}"
if [ "$DEDUP" -eq 1 ] && [ "$ENGINE" != "ffmpeg_scale" ]; then
  _DEDUP_TMP=$(mktemp --suffix=.mp4)
  printf '[dedup] Filtering duplicate frames (mpdecimate)…\n' >&2
  ffmpeg -i "$INPUT" -vf mpdecimate -vsync vfr \
    -c:v libx264 -crf 0 -preset ultrafast -an \
    "$_DEDUP_TMP" -y -loglevel error 2>&1 >&2
  _DEDUP_UNIQ=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames \
    -of csv=p=0 "$_DEDUP_TMP" 2>/dev/null)
  printf '[dedup] %s → %s unique frames (%.1f%% unique)\n' \
    "${_DEDUP_ORIG_FRAMES:-?}" "${_DEDUP_UNIQ:-?}" \
    "$(echo "${_DEDUP_UNIQ:-0} ${_DEDUP_ORIG_FRAMES:-1}" | awk '{printf "%.1f", $1/$2*100}')" >&2
  _FRAMES=${_DEDUP_UNIQ:-$_FRAMES}
  CMD[2]="$_DEDUP_TMP"
fi

# Calibration probe: extract 30 frames → upscale → measure fps → print ETA
if [ "$CALIBRATE" -eq 1 ] && [ "$ENGINE" != "ffmpeg_scale" ]; then
  _PROBE_DIR=$(mktemp -d)
  _PROBE_IN="$_PROBE_DIR/probe_in.mp4"
  _PROBE_OUT="$_PROBE_DIR/probe_out.mp4"
  _PROBE_SEEK=$(printf '%s' "$_DUR" | awk '{printf "%.1f", $1 * 0.3}')
  ffmpeg -ss "$_PROBE_SEEK" -i "$INPUT" -vframes 30 -c:v libx264 -an \
    "$_PROBE_IN" -y -v error 2>/dev/null \
    || ffmpeg -i "$INPUT" -vframes 30 -c:v libx264 -an \
    "$_PROBE_IN" -y -v error 2>/dev/null || true
  if [ -f "$_PROBE_IN" ]; then
    printf '[probe] Upscaling 30 frames with %s …\n' "$ENGINE" >&2
    case $ENGINE in
      realesrgan_video) _PCMD=("$VIDEO2X" -i "$_PROBE_IN" -o "$_PROBE_OUT" -s "$SCALE" -p realesrgan --realesrgan-model realesr-animevideov3) ;;
      realesrgan)       _PCMD=("$VIDEO2X" -i "$_PROBE_IN" -o "$_PROBE_OUT" -s "$SCALE" -p realesrgan --realesrgan-model realesrgan-plus) ;;
      realcugan)        _PCMD=("$VIDEO2X" -i "$_PROBE_IN" -o "$_PROBE_OUT" -s "$SCALE" -p realcugan --realcugan-model models-se) ;;
      anime4k)          _PCMD=("$VIDEO2X" -i "$_PROBE_IN" -o "$_PROBE_OUT" -s "$SCALE" -p libplacebo --libplacebo-shader anime4k-v4-a) ;;
    esac
    _PT0=$SECONDS
    "${_PCMD[@]}" >/dev/null 2>&1 || true
    _ELAPSED=$(( SECONDS - _PT0 ))
    if [ "$_ELAPSED" -gt 0 ]; then
      _MFPS=$(echo "30 $_ELAPSED" | awk '{printf "%.2f", $1/$2}')
      # total frames estimate for ETA
      _TOTAL_F=${_FRAMES:-$(echo "$_DUR" | awk '{printf "%d", $1 * 25}')}
      _ETA_S=$(echo "$_TOTAL_F $_MFPS" | awk '{printf "%d", $1/$2}')
      printf '[probe] measured %.2f fps → ETA %02d:%02d:%02d for %s frames\n' \
        "$_MFPS" \
        "$((_ETA_S / 3600))" "$(((_ETA_S % 3600) / 60))" "$((_ETA_S % 60))" \
        "${_TOTAL_F:-?}" >&2
      if [ "$_ETA_S" -gt 0 ]; then
        _NEED_PROBE_KB=$(echo "$_ETA_S $_BIT_KBPS $SCALE" \
          | awk '{printf "%d", $1 * $2 * $3 * $3 / 8}')
        if [ "$FREE_KB" -lt "$_NEED_PROBE_KB" ]; then
          printf '[probe] WARNING: estimated output ~%d GB, only %d GB free\n' \
            "$((_NEED_PROBE_KB / 1048576))" "$((FREE_KB / 1048576))" >&2
        fi
      fi
    fi
    rm -rf "$_PROBE_DIR"
  else
    printf '[probe] could not extract probe clip; skipping calibration\n' >&2
    rm -rf "$_PROBE_DIR"
  fi
fi

# Chunked processing + resume
# Segments input into CHUNK_SECS-second clips, upscales each, then concats.
# State: OUTPUT.chunks/<N>.json sidecar per chunk (status: done|running|pending).
# Resume (-r): chunks with existing upscaled output are skipped.
if [ "$CHUNK_SECS" -gt 0 ] && [ "$ENGINE" != "ffmpeg_scale" ]; then
  _CHUNK_DIR="${OUTPUT}.chunks"
  mkdir -p "$_CHUNK_DIR"
  _STATE_FILE="${OUTPUT}.chunks.json"

  # Compute number of chunks (ceiling div)
  _N_CHUNKS=$(echo "$_DUR $CHUNK_SECS" | awk '{n=int($1/$2); if(n*$2<$1) n++; print n}')
  printf '[chunk] %s chunks of %s s each\n' "$_N_CHUNKS" "$CHUNK_SECS" >&2

  # Phase 1: segment
  _CHUNK_LIST="$_CHUNK_DIR/chunks.txt"
  if [ ! -f "$_CHUNK_LIST" ] || [ "$RESUME" -eq 0 ]; then
    printf '[chunk] segmenting…\n' >&2
    ffmpeg -i "$INPUT" -c copy -f segment \
      -segment_time "$CHUNK_SECS" -reset_timestamps 1 \
      -segment_list "$_CHUNK_LIST" \
      "$_CHUNK_DIR/src_%05d.mp4" -y -v error 2>&1 >&2
  fi

  # Phase 2: upscale each chunk
  _C_PASS=0; _C_FAIL=0
  while IFS= read -r _chunk_src; do
    _chunk_src_path="$_CHUNK_DIR/$_chunk_src"
    _chunk_idx="${_chunk_src%.*}"; _chunk_idx="${_chunk_idx##*_}"
    _chunk_out="$_CHUNK_DIR/out_${_chunk_idx}.mp4"
    _chunk_sidecar="$_CHUNK_DIR/out_${_chunk_idx}.json"

    # Write initial chunk state
    printf '{"chunk":%d,"total":%d,"status":"pending"}\n' \
      "$((_chunk_idx + 0))" "$_N_CHUNKS" > "$_chunk_sidecar"

    if [ "$RESUME" -eq 1 ] && [ -f "$_chunk_out" ]; then
      printf '[chunk %s] skip (done)\n' "$_chunk_idx" >&2
      printf '{"chunk":%d,"total":%d,"status":"done"}\n' \
        "$((_chunk_idx + 0))" "$_N_CHUNKS" > "$_chunk_sidecar"
      _C_PASS=$((_C_PASS + 1)); continue
    fi

    printf '[chunk %s/%s] upscaling…\n' "$((_chunk_idx + 1))" "$_N_CHUNKS" >&2
    printf '{"chunk":%d,"total":%d,"status":"running"}\n' \
      "$((_chunk_idx + 0))" "$_N_CHUNKS" > "$_chunk_sidecar"

    case $ENGINE in
      realesrgan_video) _CCMD=("$VIDEO2X" -i "$_chunk_src_path" -o "$_chunk_out" -s "$SCALE" -p realesrgan --realesrgan-model realesr-animevideov3) ;;
      realesrgan)       _CCMD=("$VIDEO2X" -i "$_chunk_src_path" -o "$_chunk_out" -s "$SCALE" -p realesrgan --realesrgan-model realesrgan-plus) ;;
      realcugan)        _CCMD=("$VIDEO2X" -i "$_chunk_src_path" -o "$_chunk_out" -s "$SCALE" -p realcugan --realcugan-model models-se) ;;
      anime4k)          _CCMD=("$VIDEO2X" -i "$_chunk_src_path" -o "$_chunk_out" -s "$SCALE" -p libplacebo --libplacebo-shader anime4k-v4-a) ;;
    esac
    set +e
    "${_CCMD[@]}" >/dev/null 2>&1
    _cec=$?
    set -e
    if [ "$_cec" -eq 0 ] && [ -f "$_chunk_out" ]; then
      printf '{"chunk":%d,"total":%d,"status":"done"}\n' \
        "$((_chunk_idx + 0))" "$_N_CHUNKS" > "$_chunk_sidecar"
      _C_PASS=$((_C_PASS + 1))
    else
      printf '{"chunk":%d,"total":%d,"status":"failed"}\n' \
        "$((_chunk_idx + 0))" "$_N_CHUNKS" > "$_chunk_sidecar"
      printf '[chunk %s] FAILED (exit %d) — re-run with -r to resume\n' \
        "$_chunk_idx" "$_cec" >&2
      _C_FAIL=$((_C_FAIL + 1))
    fi
  done < "$_CHUNK_LIST"

  if [ "$_C_FAIL" -gt 0 ]; then
    printf 'Chunked encode: %d/%d chunks failed — resume with -C %s -r\n' \
      "$_C_FAIL" "$_N_CHUNKS" "$CHUNK_SECS" >&2
    exit 3
  fi

  # Phase 3: concat
  printf '[chunk] all %d chunks done — concatenating\n' "$_C_PASS" >&2
  _CONCAT_LIST="$_CHUNK_DIR/concat.txt"
  : > "$_CONCAT_LIST"
  while IFS= read -r _chunk_src; do
    _chunk_idx="${_chunk_src%.*}"; _chunk_idx="${_chunk_idx##*_}"
    printf "file 'out_%s.mp4'\n" "$_chunk_idx" >> "$_CONCAT_LIST"
  done < "$_CHUNK_LIST"
  ffmpeg -f concat -safe 0 -i "$_CONCAT_LIST" -c copy "$OUTPUT" -y -v error 2>&1 >&2

  printf '[chunk] concat complete → %s\n' "$OUTPUT" >&2
  printf '[ok] chunked encode done: %d chunks\n' "$_C_PASS" >&2

  if [ "$JSON_OUT" -eq 1 ]; then
    printf '{"input":"%s","output":"%s","quality":"%s","engine":"%s","scale":%s,"chunks":%d,"integrity_ok":true}\n' \
      "$INPUT" "$OUTPUT" "${QUALITY:-medium}" "$ENGINE" "$SCALE" "$_C_PASS"
  fi
  exit 0
fi

_AUDIT_JOB_START=$SECONDS

# Sidecar for TUI reattach (AI engines only; ffmpeg_scale has its own progress)
_SIDECAR=""
if [ "$ENGINE" != "ffmpeg_scale" ]; then
  _SIDECAR="${OUTPUT}.progress.json"
  printf '{"status":"running","pct":0,"fps":"0","remaining":""}\n' > "$_SIDECAR"
fi

_write_sidecar_vid() {
  [ -z "$_SIDECAR" ] && return 0
  printf '%s\n' "$1" > "$_SIDECAR"
}

# Detect total frame count for video2x engines (used for ETA and sidecar progress).
# ffmpeg_scale uses ffmpeg's native progress display, so skip this for that engine.
if [ "$ENGINE" != "ffmpeg_scale" ]; then
  _FRAMES=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=nb_frames -of csv=p=0 "$INPUT" 2>/dev/null)
  # some containers don't store nb_frames; fall back to duration × fps
  if [ -z "$_FRAMES" ] || [ "$_FRAMES" = "N/A" ]; then
    _DUR_S=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null)
    _FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
        -of csv=p=0 "$INPUT" 2>/dev/null | awk -F'/' '{if($2) printf "%d", $1/$2; else print $1}')
    _FRAMES=$(python3 -c "print(round(${_DUR_S:-0} * ${_FPS:-25}))" 2>/dev/null)
  fi
fi

# Progress bar for video2x output — active when a terminal is attached.
# ffmpeg_scale uses ffmpeg's native progress display.
_progress_bar() {
  local tty=/dev/tty
  [ -w "$tty" ] 2>/dev/null || tty=/dev/stderr
  local w=40 line cur tot fps rem pct filled bar
  while IFS= read -r line; do
    # Strip ANSI escape codes and carriage returns
    line=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\r//g; s/^\[K//')
    if printf '%s' "$line" | grep -qE 'frame=[0-9]+/[0-9]+'; then
      cur=$(printf '%s' "$line" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+')
      tot=$(printf '%s' "$line" | grep -oE '/[0-9]+[^0-9]' | head -1 | tr -dc '0-9')
      fps=$(printf '%s' "$line" | grep -oE 'fps=[0-9.]+' | head -1 | cut -d= -f2)
      rem=$(printf '%s' "$line" | grep -oE 'remaining=[0-9:]+' | head -1 | cut -d= -f2)
      [ -n "$tot" ] && [ "$tot" -gt 0 ] && pct=$((cur * 100 / tot)) || pct=0
      filled=$((pct * w / 100))
      bar=$(printf '%*s' "$filled" '' | tr ' ' '=')$(printf '%*s' "$((w - filled))" '' | tr ' ' '-')
      printf '\r  [%s] %3d%%  fps: %-5s  remaining: %-9s' \
        "$bar" "$pct" "${fps:--}" "${rem:---:--:--}" >"$tty"
    else
      case $line in
        *'[info]'*|*'[warning]'*|*'[error]'*)
          printf '\n%s\n' "$line" >"$tty" ;;
      esac
    fi
  done
  printf '\n' >"$tty"
}

if [ "$ENGINE" = "ffmpeg_scale" ]; then
  "${CMD[@]}" || { printf 'ffmpeg failed (exit %d)\n' "$?" >&2; exit 3; }
elif [ -t 1 ] || [ -t 2 ]; then
  "${CMD[@]}" 2>&1 | _progress_bar || true
  _ec=${PIPESTATUS[0]}
  [ "$_ec" -eq 0 ] \
    || { _write_sidecar_vid '{"status":"failed"}'; printf 'video2x failed (exit %d)\n' "$_ec" >&2; exit "$_ec"; }
else
  # Non-TTY path (used by TUI): pass output through while updating sidecar.
  set +e
  "${CMD[@]}" 2>&1 | while IFS= read -r _line; do
    printf '%s\n' "$_line" >&2
    _clean=$(printf '%s' "$_line" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\r//g')
    case $_clean in
      *frame=[0-9]*/[0-9]*)
        _cur=$(printf '%s' "$_clean" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | head -1)
        _tot=$(printf '%s' "$_clean" | grep -oE '/[0-9]+' | head -1 | tr -dc '0-9')
        _fps=$(printf '%s' "$_clean" | grep -oE 'fps=[0-9.]+' | cut -d= -f2)
        _rem=$(printf '%s' "$_clean" | grep -oE 'remaining=[^ ;]+' | cut -d= -f2)
        [ -n "$_tot" ] && [ "$_tot" -gt 0 ] && _pct=$((_cur * 100 / _tot)) || _pct=0
        printf '{"status":"running","pct":%d,"fps":"%s","remaining":"%s"}\n' \
          "$_pct" "${_fps:-0}" "${_rem:-}" > "$_SIDECAR" ;;
    esac
  done
  _ec=${PIPESTATUS[0]}
  set -e
  [ "$_ec" -eq 0 ] \
    || { _write_sidecar_vid '{"status":"failed"}'; printf 'video2x failed (exit %d)\n' "$_ec" >&2; exit "$_ec"; }
fi

_write_sidecar_vid '{"status":"done","pct":100}'
_thermal_sleep

# Dedup restoration: upscaling ran on deduplicated frames; restore original framerate
# by re-fps'ing to match source and muxing original audio.
if [ -n "$_DEDUP_TMP" ] && [ -f "$OUTPUT" ]; then
  printf '[dedup] Restoring original framerate and muxing audio…\n' >&2
  _DEDUP_RESTORED=$(mktemp --suffix=.mp4)
  _ORIG_FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
    -of csv=p=0 "$INPUT" 2>/dev/null | awk -F'/' '{if($2) printf "%.6f", $1/$2; else print $1}')
  ffmpeg -i "$OUTPUT" -i "$INPUT" \
    -vf "fps=${_ORIG_FPS:-25}" \
    -map 0:v -map 1:a? \
    -c:v libx264 -crf 18 -preset fast -c:a copy \
    "$_DEDUP_RESTORED" -y -loglevel error 2>&1 >&2 \
    && mv "$_DEDUP_RESTORED" "$OUTPUT" \
    || { printf '[dedup] framerate restore failed — keeping deduplicated output\n' >&2
         rm -f "$_DEDUP_RESTORED"; }
  rm -f "$_DEDUP_TMP"
  _thermal_sleep
fi

# NVENC re-encode: replace video2x output with h264_nvenc encode for smaller file + HDR
if [ "$NVENC" -eq 1 ] && [ -f "$OUTPUT" ]; then
  printf '[nvenc] Re-encoding with h264_nvenc (p7 preset, CQ 18)…\n' >&2
  _NVENC_TMP=$(mktemp --suffix=.mp4)
  ffmpeg -i "$OUTPUT" -i "$INPUT" \
    -map 0:v -map 1:a? \
    -c:v h264_nvenc -preset p7 -cq 18 -c:a copy \
    "$_NVENC_TMP" -y -loglevel error 2>&1 >&2 \
    && mv "$_NVENC_TMP" "$OUTPUT" \
    || { printf '[nvenc] h264_nvenc failed — keeping libx264 output\n' >&2
         rm -f "$_NVENC_TMP"; }
  _thermal_sleep
fi

# Frame interpolation: double framerate via RIFE binary or ffmpeg minterpolate fallback
if [ -n "$INTERPOLATE" ] && [ -f "$OUTPUT" ]; then
  _INTERP_TMP=$(mktemp --suffix=.mp4)
  _OUT_FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
    -of csv=p=0 "$OUTPUT" 2>/dev/null | awk -F'/' '{if($2) printf "%.6f", $1/$2; else print $1}')
  case $INTERPOLATE in
    2x)
      _TARGET_FPS=$(echo "${_OUT_FPS:-25}" | awk '{printf "%.6f", $1*2}')
      if command -v rife >/dev/null 2>&1; then
        printf '[interpolate] RIFE 2× (%s → %s fps)…\n' "${_OUT_FPS:-?}" "${_TARGET_FPS}" >&2
        rife -i "$OUTPUT" -o "$_INTERP_TMP" -m rife-v4.6 2>&1 >&2 \
          && mv "$_INTERP_TMP" "$OUTPUT" \
          || { printf '[interpolate] RIFE failed — keeping original framerate\n' >&2
               rm -f "$_INTERP_TMP"; }
      else
        printf '[interpolate] rife not found; using ffmpeg minterpolate (%s → %s fps)…\n' \
          "${_OUT_FPS:-?}" "${_TARGET_FPS}" >&2
        ffmpeg -i "$OUTPUT" \
          -vf "minterpolate=fps=${_TARGET_FPS}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1" \
          -c:v libx264 -crf 18 -preset fast -c:a copy \
          "$_INTERP_TMP" -y -loglevel error 2>&1 >&2 \
          && mv "$_INTERP_TMP" "$OUTPUT" \
          || { printf '[interpolate] minterpolate failed — keeping original framerate\n' >&2
               rm -f "$_INTERP_TMP"; }
      fi
      ;;
  esac
  _thermal_sleep
fi

# Post-mux integrity check: duration drift ≤ 100 ms, frame count match, A/V sync ≤ 40 ms
_integrity_ok=1
if [ -f "$OUTPUT" ]; then
  _OUT_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUTPUT" 2>/dev/null)
  _DRIFT=$(echo "$_DUR $_OUT_DUR" | awk '{d=$1-$2; if(d<0)d=-d; printf "%d", d*1000}')
  if [ "${_DRIFT:-9999}" -gt 100 ]; then
    printf 'INTEGRITY: duration drift %d ms (input=%.3f s, output=%.3f s)\n' \
      "$_DRIFT" "$_DUR" "${_OUT_DUR:-0}" >&2
    _integrity_ok=0
  fi
  # Frame count match (only when we have a reliable total)
  if [ -n "${_FRAMES:-}" ] && [ "$_FRAMES" -gt 0 ]; then
    _OUT_FRAMES=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=nb_frames -of csv=p=0 "$OUTPUT" 2>/dev/null)
    if [ -n "$_OUT_FRAMES" ] && [ "$_OUT_FRAMES" != "N/A" ]; then
      _FDIFF=$(( (_OUT_FRAMES - _FRAMES) < 0 ? (_FRAMES - _OUT_FRAMES) : (_OUT_FRAMES - _FRAMES) ))
      if [ "$_FDIFF" -gt 2 ]; then
        printf 'INTEGRITY: frame count mismatch input=%s output=%s (diff=%d)\n' \
          "$_FRAMES" "$_OUT_FRAMES" "$_FDIFF" >&2
        _integrity_ok=0
      fi
    fi
  fi
  # A/V sync: compare first audio PTS vs first video PTS
  _VID_START=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=start_time -of csv=p=0 "$OUTPUT" 2>/dev/null)
  _AUD_START=$(ffprobe -v error -select_streams a:0 \
    -show_entries stream=start_time -of csv=p=0 "$OUTPUT" 2>/dev/null)
  if [ -n "${_VID_START:-}" ] && [ -n "${_AUD_START:-}" ] \
     && [ "$_VID_START" != "N/A" ] && [ "$_AUD_START" != "N/A" ]; then
    _AV_DRIFT=$(echo "$_VID_START $_AUD_START" \
      | awk '{d=$1-$2; if(d<0)d=-d; printf "%d", d*1000}')
    if [ "${_AV_DRIFT:-0}" -gt 40 ]; then
      printf 'INTEGRITY: A/V sync drift %d ms\n' "$_AV_DRIFT" >&2
      _integrity_ok=0
    fi
  fi
  if [ "$_integrity_ok" -eq 1 ]; then
    printf '[ok] integrity check passed\n' >&2
  else
    printf 'INTEGRITY: check failed — review output before use\n' >&2
  fi
fi

if [ "$JSON_OUT" -eq 1 ]; then
  printf '{"input":"%s","output":"%s","quality":"%s","engine":"%s","scale":%s,"integrity_ok":%s}\n' \
    "$INPUT" "$OUTPUT" "${QUALITY:-medium}" "$ENGINE" "$SCALE" \
    "$([ "$_integrity_ok" -eq 1 ] && printf 'true' || printf 'false')"
fi

# Per-job audit manifest
if [ "$DRY_RUN" -eq 0 ] && [ -f "$OUTPUT" ]; then
  _AUDIT_ELAPSED=$(( SECONDS - _AUDIT_JOB_START ))
  _IN_HASH=""; _OUT_HASH=""
  if command -v sha256sum >/dev/null 2>&1; then
    _IN_HASH=$(sha256sum "$INPUT"  2>/dev/null | awk '{print $1}')
    _OUT_HASH=$(sha256sum "$OUTPUT" 2>/dev/null | awk '{print $1}')
  fi
  _AUDIT_WARN=""
  [ "$_integrity_ok" -eq 0 ] && _AUDIT_WARN="integrity-check-failed"
  printf '{"version":1,"media_type":"video","input":"%s","output":"%s","input_sha256":"%s","output_sha256":"%s","quality":"%s","engine":"%s","scale":%s,"dedup":%s,"interpolate":"%s","thermal_mode":"%s","nvenc":%s,"elapsed_s":%d,"integrity_ok":%s,"warnings":"%s","ts":"%s"}\n' \
    "$INPUT" "$OUTPUT" "${_IN_HASH:-}" "${_OUT_HASH:-}" \
    "${QUALITY:-medium}" "$ENGINE" "$SCALE" \
    "$([ "$DEDUP" -eq 1 ] && printf 'true' || printf 'false')" \
    "${INTERPOLATE:-}" "$THERMAL_MODE" \
    "$([ "$NVENC" -eq 1 ] && printf 'true' || printf 'false')" \
    "$_AUDIT_ELAPSED" \
    "$([ "$_integrity_ok" -eq 1 ] && printf 'true' || printf 'false')" \
    "${_AUDIT_WARN:-}" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "${OUTPUT}.audit.json" 2>/dev/null || true
fi
