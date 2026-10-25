#!/usr/bin/env bash
# Rename images based on the EXIF "date taken" (DateTimeOriginal).
# Result looks like: 2024-07-14_18-32-05.jpg
# Duplicates (same second) get a suffix: 2024-07-14_18-32-05-1.jpg
#
# Requires exiftool:  brew install exiftool
#
# Usage:
#   ./rename_by_exif.sh [-n] [-r] [folder]
#     -n   dry run (show what would be renamed, change nothing)
#     -r   recurse into subfolders
#     folder defaults to the current directory

set -euo pipefail

DRY_RUN=0
RECURSE=()

while getopts "nr" opt; do
  case "$opt" in
    n) DRY_RUN=1 ;;
    r) RECURSE=(-r) ;;
    *) echo "Usage: $0 [-n] [-r] [folder]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

DIR="${1:-.}"

if ! command -v exiftool >/dev/null 2>&1; then
  echo "exiftool not found. Install it with: brew install exiftool" >&2
  exit 1
fi

if [[ ! -d "$DIR" ]]; then
  echo "Not a directory: $DIR" >&2
  exit 1
fi

# -TestName only prints the planned rename; -FileName actually renames.
if [[ $DRY_RUN -eq 1 ]]; then
  TAG="TestName"
  echo "Dry run, no files will be changed."
else
  TAG="FileName"
fi

# %%-c adds -1, -2, ... only when a name collision occurs.
# %%le keeps the original extension, lowercased.
exiftool \
  "${RECURSE[@]}" \
  -ext jpg -ext jpeg -ext heic -ext png -ext tif -ext tiff \
  -ext cr2 -ext cr3 -ext nef -ext arw -ext dng -ext orf -ext raf \
  -if '$DateTimeOriginal' \
  -d '%Y-%m-%d_%H-%M-%S%%-c.%%le' \
  "-${TAG}<DateTimeOriginal" \
  "$DIR"

echo "Done. Files without a DateTimeOriginal tag were skipped."
