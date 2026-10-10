#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -le 2 ]] || { echo "usage: $0 [SOURCE.png [OUTPUT.icns]]" >&2; exit 64; }
SOURCE="${1:-$ROOT_DIR/Resources/AppIcon-source.png}"
OUTPUT="${2:-$ROOT_DIR/Resources/AppIcon.icns}"
[[ -f "$SOURCE" ]] || { echo "Icon source is missing: $SOURCE" >&2; exit 1; }
PROPERTIES="$(/usr/bin/sips -g format -g pixelWidth -g pixelHeight "$SOURCE")"
FORMAT="$(awk '/^[[:space:]]*format:/ {print $2}' <<< "$PROPERTIES")"
WIDTH="$(awk '/^[[:space:]]*pixelWidth:/ {print $2}' <<< "$PROPERTIES")"
HEIGHT="$(awk '/^[[:space:]]*pixelHeight:/ {print $2}' <<< "$PROPERTIES")"
[[ "$FORMAT" == png && "$WIDTH" == 1024 && "$HEIGHT" == 1024 ]] || {
  echo "Icon source must be a 1024 x 1024 PNG: $SOURCE (format=$FORMAT, ${WIDTH}x${HEIGHT})" >&2
  exit 1
}
WORK_DIR="$(mktemp -d /private/tmp/labelprint-icon.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  /usr/bin/sips -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  if [[ "$DOUBLE" == 1024 ]]; then
    cp "$SOURCE" "$ICONSET/icon_${SIZE}x${SIZE}@2x.png"
  else
    /usr/bin/sips -z "$DOUBLE" "$DOUBLE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  fi
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$WORK_DIR/AppIcon.icns"
mkdir -p "$(dirname "$OUTPUT")"
cp "$WORK_DIR/AppIcon.icns" "$OUTPUT"
printf 'Created: %s\n' "$OUTPUT"
