#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/project.env
[[ $# -eq 1 && "$1" == "$VERSION" ]] || { echo "usage: $0 $VERSION" >&2; exit 64; }
[[ "$(uname -m)" == arm64 ]] || { echo 'Release requires Apple Silicon.' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the reviewed source before building a release.' >&2; exit 1; }
SOURCE_COMMIT="$(git rev-parse HEAD)"
IDENTITY="${MACOS_SIGNING_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"
PROFILE="${MACOS_NOTARY_PROFILE:-$DEFAULT_NOTARY_PROFILE}"
IDENTITIES="$(security find-identity -v -p codesigning)"
grep -F "$IDENTITY" <<< "$IDENTITIES" >/dev/null
OUT="$ROOT_DIR/dist/releases/$VERSION"
ZIP="$OUT/LabelPrint-$VERSION-macOS-arm64.zip"
[[ ! -e "$ZIP" ]] || { echo "Artifact already exists; verify it instead of overwriting: $ZIP" >&2; exit 1; }
mkdir -p "$OUT"
WORK="$(mktemp -d "$OUT/work.XXXXXX")"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
swift test --disable-sandbox
swift run --disable-sandbox LabelPrintCheck "$WORK/raster-check"
./script/build_and_run.sh --release-build
APP="$WORK/LabelPrint.app"
ditto dist/release-build/LabelPrint.app "$APP"
[[ "$(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE_NAME")" == arm64 ]]
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
codesign --verify --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/submission.zip"
xcrun notarytool submit "$WORK/submission.zip" --keychain-profile "$PROFILE" --output-format json > "$WORK/submission.json"
cat "$WORK/submission.json"
SUBMISSION_ID="$(plutil -extract id raw -o - "$WORK/submission.json")"
printf '%s\n' "$SUBMISSION_ID" > "$OUT/submission-id.txt"
set +e
xcrun notarytool wait "$SUBMISSION_ID" --keychain-profile "$PROFILE" --timeout 30m --output-format json > "$WORK/result.json"
WAIT_RESULT=$?
set -e
cat "$WORK/result.json"
if [[ $WAIT_RESULT -ne 0 || "$(plutil -extract status raw -o - "$WORK/result.json" 2>/dev/null || true)" != Accepted ]]; then
  xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" "$WORK/notary-log.json" || true
  echo "Not accepted yet. Preserve $WORK and query submission $SUBMISSION_ID; do not resubmit blindly." >&2
  exit 1
fi
xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" "$OUT/notary-log.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
./script/verify_release.sh "$ZIP" | tee "$OUT/verification.txt"
printf '%s\n' "$SOURCE_COMMIT" > "$OUT/source-commit.txt"
echo "Local release ready: $ZIP"
