# LabelPrint – project handoff

## Product

Native macOS PDF label app for Phomemo D520BT, 103 × 199 mm. Local processing,
no vendor driver, no account or cloud service. GPL-3.0-only. German app UI,
German and English documentation. Public repository: r3d42-git/LabelPrint.

## Confirmed functionality

The user tested multiple real PDF variants on the physical printer: mouse cropping,
proportional fitting and printing worked, and all tested QR/barcodes were readable.
BLE is the working transport. Classic repeatedly timed out during connection and
remains experimental. No additional product features are needed for this release.

At 8 dots/mm the final raster is 824 × 1592. White margins are at least 3 mm.
BITMAP mode 0 on this D520 uses wire bits 0=black, 1=white. Internal raster bits differ.
Sparse disjoint tiles preserve every pixel; the reference job shrank from 164117 to
31122 bytes. The user confirmed normal polarity and noticeably faster transfer.
BLE service FF00 / write FF02 / notification FF01; keep the proven write-with-response
mode. Observed printer replies: SSSGETPRINTING:DOING and SSSGETPRINTING:DONE.

## Structure

- `LabelTestCore`: final mono raster, TSPL jobs, PDF snapshot/rendering, crop geometry,
  fragmented printer-reply parser.
- `LabelPrintTest`: SwiftUI app, narrow AppKit crop canvas, background PDF workspace,
  CoreBluetooth/IOBluetooth transport.
- `LabelPrintCheck`: offline independent TSPL reconstruction and Vision QR/Code128 check;
  `--pdf` mode for page/crop/rotation output, never sends to hardware.
- `Tests/LabelTestCoreTests`: 15 tests covering PDF rotations/crops, margins, code decoding,
  invalid input, immutable snapshots, raster/TSPL and printer replies.
- `docs`: GitHub Pages and editable, source-backed Archify diagram.

## Release contract

`script/project.env` is the release metadata source. Version 0.2.1, build 4,
Apple Silicon arm64, macOS 14+. Product bundle LabelPrint.app; legacy internal executable
LabelPrintTest and bundle ID de.r3d.labelprint.test are retained for continuity.

`script/release.sh 0.2.1`: clean-source tests, optimized build, Developer ID + Hardened
Runtime + timestamp, Apple submission, Accepted gate, app staple, ZIP/checksum and
fresh extraction verification. Existing local Keychain profile: LabelPrint. Credentials
never enter source control. `script/publish_release.sh --dry-run 0.2.1` checks the
exact source commit and local artifact. Publication separately pushes main/tag, creates
the GitHub release and independently downloads/verifies exact public bytes.

No clean-machine installation or Intel build has been validated. Physical PDF success
was established on the user's Mac before release packaging. The release does not install
or change an existing app automatically. Original vendor packages and PDFs stay untracked.

## Verification evidence

15 tests passed during implementation. QR and Code128 decode from a cropped synthetic PDF.
The local 13-page vendor manual was also rendered (first/last page, crop and 90° rotation),
with visual checks of page orientation and rotated crop. Original files were not changed.
Final release evidence is recorded below; the published tag remains unchanged.


## Published release 0.2.0 — 2026-10-10

- Public repository: https://github.com/r3d42-git/LabelPrint
- Tag: `v0.2.0`, source/release commit: `39baf735a70ce657f3f3628a228d44f359e9e670`.
- Release: https://github.com/r3d42-git/LabelPrint/releases/tag/v0.2.0
- Asset: [LabelPrint-0.2.0-macOS-arm64.zip](https://github.com/r3d42-git/LabelPrint/releases/download/v0.2.0/LabelPrint-0.2.0-macOS-arm64.zip).
- SHA-256: `a93d1784b7e5a19bfa17704182583f6fd6cfbc94225b526a830711b1cef76c87`.
- Bundle: `de.r3d.labelprint.test`, version 0.2.0/build 3, arm64, macOS 14+.
- Signing: Developer ID Application: Philipp John Hild (`G6JH37W285`), Hardened Runtime,
  secure timestamp. No additional entitlements required; no App Sandbox.
- Apple submission: `066b8dcc-b360-4c86-953f-6b3cd56b2460`, Accepted; app ticket stapled
  before final ZIP packaging. Strict signature, app staple, Gatekeeper and
  `syspolicy_check distribution` passed both locally and on a fresh public download.
- Local ZIP, downloaded ZIP and GitHub's reported SHA-256 digest agree exactly.
- [Release CI](https://github.com/r3d42-git/LabelPrint/actions/runs/38070104772) passed:
  15 tests, app build, offline QR/Code128 decode, release-script syntax checks.
- [Pages deployment](https://github.com/r3d42-git/LabelPrint/actions/runs/38070106531)
  succeeded; HTTPS enforced at https://r3d42-git.github.io/LabelPrint/.
- Live landing page SHA-256: `ad8c3f39e3ac33be49efe7e5e6082655cb0154dec0feb17dca8f1fd785c22d3b`.
- Live architecture SHA-256: `d6028b115e7deeaa20adba4d9bfb0a4d676d44267f895171c4f0447933c55638`.
  Both public HTTPS responses match the reviewed local files byte for byte.
- Archify: 9/9 showcase checks, zero errors/warnings; five verified code links pinned to
  initial source commit `7b86a658a905e0960443e04ba84efe6107dd1e21`. Browser checks at
  1440×900, 1600×1000, 1920×1080 and 2048×1320 with light/dark; visual review passed.
  Landing page checked in desktop/mobile, both themes, DE/EN toggle and no JS errors.
- Remaining boundary: the user tested the functional build on real hardware; the exact
  packaged release was certified but not launched on a separate clean Mac. No Intel release.

The public repository was created empty, then only reviewed, explicitly staged files were
pushed. Vendor packages/manuals, private PDFs, local settings and build outputs remain
excluded. No credentials, Keychain configuration or global tooling were changed.

## Icon integration for 0.2.1 — 2026-10-10

A new LabelPrint icon has been created with the built-in image-generation tool:
forest-green macOS tile, white adhesive label and dark barcode, matching the website palette.
`Resources/AppIcon-source.png` is the 1024×1024 transparent source; `Resources/ICON_PROMPT.md`
records the generation and cleanup prompts. `script/build_icon.sh` creates the standard
1×/2× macOS sizes and `Resources/AppIcon.icns` with sips/iconutil.

Development and future release builds now embed and reference AppIcon.icns. Release
verification requires the icon and compares its exact bytes against the source asset.
The local app rebuilt and launched successfully; Info.plist, embedded ICNS byte identity
and strict ad-hoc signature validation passed. Icon conversion needed a permitted local
context after sandbox-only iconutil Invalid Iconset; the same script then succeeded.
The native UI inspection bridge remained unavailable, so no Dock/Finder screenshot was
claimed. The user approved the icon and requested its integration into GitHub Pages
and publication as a new signed/notarized release. Version 0.2.1 (build 4) is prepared;
the published 0.2.0 tag and ZIP remain unchanged.
