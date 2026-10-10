#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/project.env
DRY_RUN=0
if [[ "${1:-}" == --dry-run ]]; then DRY_RUN=1; shift; fi
[[ $# -eq 1 && "$1" == "$VERSION" ]] || { echo "usage: $0 [--dry-run] $VERSION" >&2; exit 64; }
[[ "$(git branch --show-current)" == main && -z "$(git status --porcelain)" ]]
[[ "$(git remote get-url origin)" == "https://github.com/$REPOSITORY.git" ]]
OUT="$ROOT_DIR/dist/releases/$VERSION"
ZIP="$OUT/LabelPrint-$VERSION-macOS-arm64.zip"
[[ "$(cat "$OUT/source-commit.txt")" == "$(git rev-parse HEAD)" ]] || { echo 'Artifact commit differs from HEAD.' >&2; exit 1; }
[[ "$(gh repo view "$REPOSITORY" --json visibility --jq .visibility)" == PUBLIC ]]
[[ -z "$(git ls-remote --tags origin "refs/tags/v$VERSION*")" ]]
! git rev-parse --verify "refs/tags/v$VERSION" >/dev/null 2>&1
./script/verify_release.sh "$ZIP"
[[ -s RELEASE_NOTES.md ]]
if [[ "$DRY_RUN" == 1 ]]; then echo 'Publish preflight passed. No writes performed.'; exit 0; fi
git push -u origin main
git tag -a "v$VERSION" -m "LabelPrint $VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" "$ZIP.sha256" --repo "$REPOSITORY" --verify-tag --title "LabelPrint $VERSION" --notes-file RELEASE_NOTES.md
DOWNLOAD="$(mktemp -d /private/tmp/labelprint-public.XXXXXX)"
echo "Fresh public download: $DOWNLOAD"
gh release download "v$VERSION" --repo "$REPOSITORY" --dir "$DOWNLOAD" --pattern "$(basename "$ZIP")*"
cmp "$ZIP" "$DOWNLOAD/$(basename "$ZIP")"
cmp "$ZIP.sha256" "$DOWNLOAD/$(basename "$ZIP").sha256"
LOCAL_DIGEST="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
REMOTE_DIGEST="$(gh api "repos/$REPOSITORY/releases/tags/v$VERSION" --jq '.assets[] | select(.name == "LabelPrint-'"$VERSION"'-macOS-arm64.zip") | .digest')"
[[ "$REMOTE_DIGEST" == "sha256:$LOCAL_DIGEST" ]]
./script/verify_release.sh "$DOWNLOAD/$(basename "$ZIP")" | tee "$OUT/public-verification.txt"
printf '%s\n' "$DOWNLOAD" > "$OUT/public-download-directory.txt"
echo "Published and freshly verified: https://github.com/$REPOSITORY/releases/tag/v$VERSION"
