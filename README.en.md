# LabelPrint

[Deutsch](README.md) · [Download](https://github.com/r3d42-git/LabelPrint/releases/latest) · [Website & architecture](https://r3d42-git.github.io/LabelPrint/)

**Crop PDF labels locally on your Mac and print them to a D520BT over Bluetooth LE.** LabelPrint is a native macOS app with a German interface, a fixed **103 × 199 mm** label size and a preview of the exact monochrome pixels sent to the printer.

No manufacturer driver, account, cloud service or external runtime libraries. PDFs stay on your Mac; originals are never modified or overwritten. LabelPrint is an independent project with no affiliation to Phomemo or Labelife.

## Download and requirements

- **macOS 14 or later**, Apple Silicon (arm64).
- A D520BT with Bluetooth LE and matching 103 × 199 mm labels.
- [Download LabelPrint 0.2.0](https://github.com/r3d42-git/LabelPrint/releases/download/v0.2.0/LabelPrint-0.2.0-macOS-arm64.zip), extract the ZIP and move `LabelPrint.app` into Applications.
- The release page provides checksums and signing details. An Intel build is currently not available.

## Print a label

1. Choose **PDF öffnen …** (Open PDF, ⌘O), then select the desired page.
2. Drag a rectangle around the label. Zoom helps with selection; **Ganze Seite** (Whole page) resets the crop. Preserve the white quiet zones around QR codes and barcodes.
3. Check the print preview on the right and **rotate by 90°** if needed. The crop is fitted proportionally and centered with **at least 3 mm of white margin**.
4. Turn on the printer and load labels. Close other active connections to it, choose **Drucker suchen** (Find printer), allow Bluetooth access in macOS and select **D520 · BLE**.
5. **Etikett drucken** (Print label) sends exactly one label. LabelPrint connects to the selected printer when needed.

**Druckeinstellungen und Diagnose** (Print settings and diagnostics) includes density, speed, label gap, grayscale threshold, PNG export, test labels and a copyable log. Defaults: density 12, speed 3, gap 3 mm.

The job is frozen during connection and transfer. There are no automatic retries or prints when opening a PDF or connecting. After an interruption, inspect the printed result; already buffered data cannot be recalled. If necessary, power-cycle the printer before deliberately starting a new attempt.

## Print quality and limitations

PDF content is rendered directly at **824 × 1592 dots** (8 dots/mm, nominally 203 dpi), converted to 1 bit without dithering and transmitted losslessly. The page preview is not the print source. The print preview and output use the same final raster.

The user successfully cropped, fitted and printed several real PDF variants on the D520BT; all codes checked on those prints were readable. This verifies those specific prints. Other PDF contents and devices need their own paper test.

- One crop from one page per print, fixed label size; no batch printing.
- Password-protected PDFs require an unlocked copy. Flatten interactive form fields and annotations into the PDF page content first.
- Proven transport: **BLE FF00/FF02** with acknowledged writes; FF01 supplies printer replies.
- Bluetooth Classic is experimental and timed out during connection on the tested device.
- QR code and barcode readability depends on source quality, crop, quiet zones and physical print size.

## Build from source

Requires Xcode with Swift and the macOS SDKs. The SwiftPM package uses Swift 5 language mode and Apple system frameworks only.

```sh
swift test --disable-sandbox
./script/build_and_run.sh --verify
```

The development script creates `dist/LabelPrintTest.app` and launches it. The public release is named `LabelPrint.app`; internal SwiftPM target and bundle identifiers remain unchanged for compatibility.

The offline checkers do not print:

```sh
swift run --disable-sandbox LabelPrintCheck output
swift run --disable-sandbox LabelPrintCheck --pdf /path/to/example.pdf output/pdf-check
```

15 automated tests cover raster/TSPL, fragmented replies, crop geometry, PDF cropping, page rotation, white margins, error cases, immutable snapshots and QR/Code 128 recognition using Apple Vision.

## Architecture

[Explore the interactive architecture](https://r3d42-git.github.io/LabelPrint/diagrams/architecture.html). Diagram labels are German; fixed viewer controls are English.

| Area | Responsibility |
| --- | --- |
| `LabelPrintTest` | SwiftUI workspace, AppKit selection canvas, background rendering and Bluetooth transport |
| `LabelTestCore` | Immutable PDF snapshot, crop/rotation, 1-bit raster, compact TSPL jobs and reply parser |
| `LabelPrintCheck` | Local raster and PDF verification, including code recognition |

Stale rendering results cannot overwrite a newer selection. White raster regions are omitted; occupied regions are sent as TSPL `BITMAP`/`BAR`. On the tested D520, `BITMAP` mode 0 uses **0 = black, 1 = white** on the wire. `DOING`/`DONE` are printer replies and do not replace scanning the physical label.

## License and acknowledgements

[GNU GPL v3, version 3 only](LICENSE) (`GPL-3.0-only`). Public sources contain no manufacturer packages, manufacturer manuals or private shipping PDFs. Product names describe compatibility only. The embedded Archify diagram viewer is separately covered by the [MIT license](docs/diagrams/LICENSE.archify); embedded font license notices remain in the HTML.

Protocol background: [TSC TSPL/TSPL2 reference](https://fs.tscprinters.com/system/files/31-0000001-00_tspl_tspl2_programming_3_0.pdf) and [independent interoperability notes](https://github.com/thermal-label/labelife/blob/main/docs/protocol/tspl.md).
