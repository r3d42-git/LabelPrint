#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/project.env"
APP_NAME="LabelPrintTest"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
case "$MODE" in
  run|--verify|--debug|--logs|--telemetry|--build-only|--release-build) ;;
  *) echo "usage: $0 [--build-only|--release-build|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
[[ -f "$ICON_SOURCE" ]] || { echo "App icon is missing: $ICON_SOURCE. Run script/build_icon.sh first." >&2; exit 1; }
if [[ "$MODE" != "--build-only" && "$MODE" != "--release-build" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
CONFIGURATION=debug
if [[ "$MODE" == "--release-build" ]]; then
  CONFIGURATION=release
  APP_BUNDLE="$ROOT_DIR/dist/release-build/LabelPrint.app"
  SOURCE_COMMIT="$(git rev-parse --verify HEAD)"
fi
swift build --disable-sandbox -c "$CONFIGURATION" --arch arm64 --product "$APP_NAME"
BUILD_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --arch arm64 --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LabelPrintTest</string>
<key>CFBundleIdentifier</key><string>de.r3d.labelprint.test</string>
<key>CFBundleName</key><string>LabelPrint</string>
<key>CFBundleDisplayName</key><string>LabelPrint</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>LabelPrint verbindet sich auf deinen Wunsch mit dem D520BT und druckt dein Etikett.</string>
<key>NSBluetoothPeripheralUsageDescription</key><string>LabelPrint verbindet sich auf deinen Wunsch mit dem D520BT und druckt dein Etikett.</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>PDF-Dokument</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
</dict></array>
</dict></plist>
PLIST
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE"
if [[ "$MODE" == "--release-build" ]]; then
  printf 'Version: %s\nSource: https://github.com/%s/tree/%s\nSPDX-License-Identifier: GPL-3.0-only\n' "$VERSION" "$REPOSITORY" "$SOURCE_COMMIT" > "$APP_BUNDLE/Contents/Resources/BuildInfo.txt"
else
  /usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
fi
case "$MODE" in
  --build-only|--release-build) echo "$APP_BUNDLE" ;;
  --debug) /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "LabelPrintTest"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "LabelPrintTest läuft. Bluetooth und Druck werden erst durch die Bedienung ausgelöst."
    ;;
  *) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
