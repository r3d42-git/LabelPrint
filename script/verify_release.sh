#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/project.env"
[[ $# -eq 1 ]] || { echo "usage: $0 RELEASE.zip" >&2; exit 64; }
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
[[ -f "$ICON_SOURCE" ]] || { echo "App icon is missing: $ICON_SOURCE. Run script/build_icon.sh first." >&2; exit 1; }
ARCHIVE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[[ -f "$ARCHIVE" && -f "$ARCHIVE.sha256" ]] || { echo 'Archive and checksum are required.' >&2; exit 1; }
[[ "$(basename "$ARCHIVE")" == "LabelPrint-$VERSION-macOS-arm64.zip" ]]
(cd "$(dirname "$ARCHIVE")" && shasum -a 256 -c "$(basename "$ARCHIVE").sha256")
unzip -t "$ARCHIVE" >/dev/null
CHECK_DIR="$(mktemp -d /private/tmp/labelprint-verify.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
ditto -x -k "$ARCHIVE" "$CHECK_DIR"
APP="$CHECK_DIR/LabelPrint.app"
PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == "$BUNDLE_ID" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" == "$BUILD_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")" == AppIcon.icns ]] || { echo 'Bundle must reference AppIcon.icns.' >&2; exit 1; }
cmp "$ICON_SOURCE" "$APP/Contents/Resources/AppIcon.icns"
[[ "$(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE_NAME")" == arm64 ]]
cmp "$ROOT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE"
grep -F 'SPDX-License-Identifier: GPL-3.0-only' "$APP/Contents/Resources/BuildInfo.txt"
codesign --verify --strict --verbose=2 "$APP"
SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"
printf '%s\n' "$SIGNATURE"
grep -F "TeamIdentifier=$TEAM_ID" <<< "$SIGNATURE" >/dev/null
grep -F 'Authority=Developer ID Application:' <<< "$SIGNATURE" >/dev/null
grep -F '(runtime)' <<< "$SIGNATURE" >/dev/null
grep -F 'Timestamp=' <<< "$SIGNATURE" >/dev/null
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
if command -v syspolicy_check >/dev/null; then syspolicy_check distribution "$APP"; fi
cat "$APP/Contents/Resources/BuildInfo.txt"
printf 'Verified: %s\n' "$ARCHIVE"
