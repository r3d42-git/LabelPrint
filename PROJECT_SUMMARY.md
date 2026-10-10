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

`script/project.env` is the release metadata source. Version 0.2.0, build 3,
Apple Silicon arm64, macOS 14+. Product bundle LabelPrint.app; legacy internal executable
LabelPrintTest and bundle ID de.r3d.labelprint.test are retained for continuity.

`script/release.sh 0.2.0`: clean-source tests, optimized build, Developer ID + Hardened
Runtime + timestamp, Apple submission, Accepted gate, app staple, ZIP/checksum and
fresh extraction verification. Existing local Keychain profile: LabelPrint. Credentials
never enter source control. `script/publish_release.sh --dry-run 0.2.0` checks the
exact source commit and local artifact. Publication separately pushes main/tag, creates
the GitHub release and independently downloads/verifies exact public bytes.

No clean-machine installation or Intel build has been validated. Physical PDF success
was established on the user's Mac before release packaging. The release does not install
or change an existing app automatically. Original vendor packages and PDFs stay untracked.

## Verification evidence

15 tests passed during implementation. QR and Code128 decode from a cropped synthetic PDF.
The local 13-page vendor manual was also rendered (first/last page, crop and 90° rotation),
with visual checks of page orientation and rotated crop. Original files were not changed.
Final release evidence will be recorded after publication without moving its tag.
