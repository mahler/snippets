#!/usr/bin/env bash
# =============================================================================
#  transcode_x265_720p.sh
#  Transcode video files to x265/HEVC 720p.
#
#  Profile:
#    Container  : Matroska (.mkv)
#    Video      : HEVC / x265, 8-bit, Main@L3.1, CRF 28, preset slow
#    Resolution : ≤ 1280×720 (downscale only; never upscale)
#    Frame rate : Preserved from source (CFR mode)
#    Audio      : EAC3 / AC3 passed through unchanged when present;
#                 otherwise re-encoded to AAC-LC 224 kb/s (stereo) or
#                 640 kb/s (5.1/7.1 → 5.1 downmix)
#    Subtitles  : All subtitle tracks copied as-is
#    Metadata   : All stream metadata + chapters preserved
#
#  Usage:
#    Single file : ./transcode_x265_720p.sh input.mkv [output.mkv]
#    Batch mode  : ./transcode_x265_720p.sh *.mkv
#                  ./transcode_x265_720p.sh /path/to/folder/
#
#  Dependencies : ffmpeg ≥ 4.4 with libx265, ffprobe
# =============================================================================

set -euo pipefail

# ── Tunables ─────────────────────────────────────────────────────────────────
CRF=28                   # CRF 28 — good quality/size balance for 720p
PRESET="slow"            # "slow" preset for better compression efficiency
MAX_WIDTH=1280
MAX_HEIGHT=720
PIX_FMT="yuv420p"        # 8-bit 4:2:0
HEVC_PROFILE="main"      # Main profile → L3.1 for 720p
OUTPUT_SUFFIX="_720p.HEVC.x265"
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in ffmpeg ffprobe; do
    if ! command -v "$cmd" &>/dev/null; then
        error "$cmd is not installed or not in PATH."
        exit 1
    fi
done

# ── Collect input files ───────────────────────────────────────────────────────
INPUT_FILES=()
if [[ $# -eq 0 ]]; then
    error "No input file(s) specified."
    echo "Usage: $0 <file|dir|glob> [output.mkv]"
    exit 1
fi

# If first argument is a directory, glob all video files inside it
if [[ -d "$1" ]]; then
    while IFS= read -r -d '' f; do
        INPUT_FILES+=("$f")
    done < <(find "$1" -maxdepth 1 \
        \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \
           -o -iname "*.mov" -o -iname "*.ts" -o -iname "*.m2ts" \
           -o -iname "*.wmv" -o -iname "*.flv" \) \
        -print0 | sort -z)
    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        error "No supported video files found in directory: $1"
        exit 1
    fi
    EXPLICIT_OUTPUT=""
else
    # Check if second argument looks like an output filename
    if [[ $# -eq 2 && "$2" == *.mkv ]]; then
        INPUT_FILES=("$1")
        EXPLICIT_OUTPUT="$2"
    else
        for arg in "$@"; do
            [[ -f "$arg" ]] && INPUT_FILES+=("$arg")
        done
        EXPLICIT_OUTPUT=""
    fi
fi

if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
    error "No valid input files found."
    exit 1
fi

# ── Scale filter builder ──────────────────────────────────────────────────────
# Downscales to 720p while preserving aspect ratio. Never upscales.
# Ensures width and height are both divisible by 2 (required for x265).
build_scale_filter() {
    local src_w=$1 src_h=$2
    if (( src_w <= MAX_WIDTH && src_h <= MAX_HEIGHT )); then
        # Already fits — no scaling needed, but enforce even dimensions
        echo "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    else
        # Scale down to fit within 1280×720, keep aspect ratio, force even dims
        echo "scale='if(gt(iw/ih,${MAX_WIDTH}/${MAX_HEIGHT}),${MAX_WIDTH},-2)':'if(gt(iw/ih,${MAX_WIDTH}/${MAX_HEIGHT}),-2,${MAX_HEIGHT})':flags=lanczos,scale=trunc(iw/2)*2:trunc(ih/2)*2"
    fi
}

# ── Audio strategy ───────────────────────────────────────────────────────────
# EAC3/AC3/DTS/TrueHD passed through untouched; everything else → AAC-LC.
# Populates the caller's AUDIO_ARGS array (avoids word-splitting / set -u issues).
set_audio_args() {
    local input_file=$1
    local audio_codec
    audio_codec=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name -of csv=p=0 "$input_file" 2>/dev/null | head -1)

    # tr for lowercase — avoids bash 4-only ${var,,} (macOS ships bash 3)
    local audio_codec_lc
    audio_codec_lc=$(echo "$audio_codec" | tr '[:upper:]' '[:lower:]')

    case "$audio_codec_lc" in
        eac3|ac3|truehd|dts)
            AUDIO_ARGS=("-c:a" "copy")
            ;;
        *)
            local channels
            channels=$(ffprobe -v error -select_streams a:0 \
                -show_entries stream=channels -of csv=p=0 "$input_file" 2>/dev/null | head -1)
            channels=${channels:-2}   # default to stereo if probe returns empty
            channels=$(echo "$channels" | tr -cd '0-9')  # strip any stray chars
            channels=${channels:-2}   # re-default in case stripping left it empty
            if (( channels > 2 )); then
                AUDIO_ARGS=("-c:a" "aac" "-b:a" "640k" "-ac" "6")
            else
                AUDIO_ARGS=("-c:a" "aac" "-b:a" "224k" "-ac" "2")
            fi
            ;;
    esac
}

# ── Main transcode function ───────────────────────────────────────────────────
transcode_file() {
    local input_file=$1
    local output_file=$2

    info "──────────────────────────────────────────────────────────"
    info "Input  : $input_file"
    info "Output : $output_file"

    # Probe source dimensions
    local src_w src_h
    src_w=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width -of csv=p=0 "$input_file" 2>/dev/null | head -1)
    src_h=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=height -of csv=p=0 "$input_file" 2>/dev/null | head -1)

    if [[ -z "$src_w" || -z "$src_h" ]]; then
        error "Could not read video dimensions from: $input_file — skipping."
        return 1
    fi

    info "Source : ${src_w}×${src_h}"

    local scale_filter
    scale_filter=$(build_scale_filter "$src_w" "$src_h")

    AUDIO_ARGS=()
    set_audio_args "$input_file"
    info "Audio  : ${AUDIO_ARGS[*]}"

    # x265 encoding parameters
    #   open-gop, keyint=240, min-keyint=24, scenecut=40,
    #   bframes=8, b-adapt=2, rc-lookahead=40, aq-mode=2, aq-strength=1.0
    local x265_params="open-gop=1:keyint=240:min-keyint=24:scenecut=40:\
bframes=8:bframe-bias=0:b-adapt=2:rc-lookahead=40:\
aq-mode=2:aq-strength=1.0:qcomp=0.60:\
strong-intra-smoothing=1:rect=0:amp=0:\
psy-rd=0.0:psy-rdoq=0.0:rdoq-level=0:\
sao=1:deblock=-1\\,-1:\
weightp=1:weightb=0:\
log-level=warning"

    ffmpeg -hide_banner -loglevel warning -stats \
        -probesize 50M -analyzeduration 50M \
        -i "$input_file" \
        -vf "$scale_filter" \
        -c:v libx265 \
        -crf "$CRF" \
        -preset "$PRESET" \
        -profile:v "$HEVC_PROFILE" \
        -pix_fmt "$PIX_FMT" \
        -x265-params "$x265_params" \
        "${AUDIO_ARGS[@]}" \
        -c:s copy \
        -map 0 \
        -map_metadata 0 \
        -map_chapters 0 \
        -movflags +faststart \
        -y \
        "$output_file" \
    && info "Done → $output_file" \
    || { error "Encoding failed for: $input_file"; return 1; }
}

# ── Process files ─────────────────────────────────────────────────────────────
SUCCESS=0; FAIL=0

for input_file in "${INPUT_FILES[@]}"; do
    if [[ ! -f "$input_file" ]]; then
        warn "Not a file, skipping: $input_file"
        continue
    fi

    # Skip macOS resource fork ghost files (._filename)
    local basename
    basename=$(basename "$input_file")
    if [[ "$basename" == ._* ]]; then
        warn "Skipping macOS metadata file: $input_file"
        continue
    fi

    # Determine output path
    if [[ -n "${EXPLICIT_OUTPUT:-}" && ${#INPUT_FILES[@]} -eq 1 ]]; then
        output_file="$EXPLICIT_OUTPUT"
    else
        dir=$(dirname "$input_file")
        base=$(basename "$input_file")
        stem="${base%.*}"
        output_file="${dir}/${stem}${OUTPUT_SUFFIX}.mkv"
    fi

    # Skip if output already exists
    if [[ -f "$output_file" ]]; then
        warn "Output already exists, skipping: $output_file"
        continue
    fi

    if transcode_file "$input_file" "$output_file"; then
        (( SUCCESS++ )) || true
    else
        (( FAIL++ )) || true
    fi
done

echo ""
info "Batch complete — Success: $SUCCESS | Failed: $FAIL"
