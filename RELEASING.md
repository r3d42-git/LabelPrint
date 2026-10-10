# Releasing LabelPrint

Releases are built locally on Apple Silicon with Xcode. GitHub Actions runs tests and
build checks; it does not hold signing or notarization credentials or publish binaries.

## Metadata and source

Update `script/project.env` and the bilingual README, website and `RELEASE_NOTES.md` when
changing versions. Keep the tested printer protocol unchanged unless a hardware test
justifies a change. Review and commit only intended source, documentation and scripts.
Do not add vendor packages, private PDFs, `.codex`, build output or credentials.

The release branch is `main`. The distributed app is `LabelPrint.app`; the internal
executable `LabelPrintTest` and bundle ID `de.r3d.labelprint.test` are retained.
The first supported release architecture is arm64; macOS 14 is the deployment target.

## Local certification

```sh
./script/release.sh 0.2.0
./script/publish_release.sh --dry-run 0.2.0
```

The release script requires a clean Git worktree, runs tests and the offline barcode
checker, creates an optimized app, signs with Developer ID and Hardened Runtime, submits
to Apple, requires Accepted, staples the app and packages it in a ZIP. Verification
extracts the exact archive into a fresh directory and checks SHA-256, version, architecture,
license, strict signature, timestamp, Team ID, stapling and Gatekeeper.

Defaults use the existing Developer ID certificate fingerprint and Keychain profile
`LabelPrint`, referenced in `script/project.env`. `MACOS_SIGNING_IDENTITY` and
`MACOS_NOTARY_PROFILE` can override the references. Never put credentials in these variables
or source files. The scripts do not create or modify Keychain items, toolchains or settings.
Restricted execution may hide identities or deny network/compiler access: rerun in a
permitted local context before diagnosing a missing certificate or changing source.

Artifacts and evidence are in `dist/releases/VERSION/`. The app includes the GPL license
and a `BuildInfo.txt` link to its exact source revision. The final ZIP contains an already
stapled app; ZIP files themselves cannot receive stapled tickets.

On an interrupted notarization, keep `submission-id.txt` and query that submission with
`xcrun notarytool info ID --keychain-profile LabelPrint`. Do not submit identical bytes again
while status is unknown. On rejection inspect the saved notary log before repairing.
The wrapper refuses to overwrite an existing final archive.

## Publication and public download

```sh
./script/publish_release.sh 0.2.0
```

This verifies clean `main`, the intended remote, unused tag and the artifact's source
commit; pushes `main`, creates/pushes an annotated version tag, uploads ZIP and checksum,
then downloads them into a fresh directory. Local bytes, public bytes and GitHub's asset
digest must agree, and the downloaded app must pass the same certification checks.

If a publication step fails after an external write, inspect actual GitHub state before
continuing. Never force a tag or silently replace an asset. The script deliberately stops
on existing tags; it is not an automatic partial-publication recovery tool.

Record final tag/source commit, checksum, notarization ID, CI and download evidence in
`PROJECT_SUMMARY.md` using a subsequent documentation-only commit; never move the release tag.
GitHub Pages serves `main:/docs`; architecture source links are pinned to the reviewed code
revision. The generated Archify viewer retains its separate MIT license notice.
