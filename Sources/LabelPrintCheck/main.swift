import Foundation
import LabelTestCore
import Vision

// Optional offline PDF smoke check; never creates a printer connection.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--pdf" {
    do {
        let document = try PDFLabelDocument(url: URL(fileURLWithPath: CommandLine.arguments[2]))
        let directory = URL(fileURLWithPath: CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "output/pdf-check", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, crop, turns) in [("ganze-seite", CGRect(x: 0, y: 0, width: 1, height: 1), 0),
                                   ("ausschnitt", CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.4), 0),
                                   ("ausschnitt-90", CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.4), 1)] {
            let raster = try document.renderLabel(at: 0, crop: crop, quarterTurns: turns)
            try raster.writePNG(to: directory.appendingPathComponent(name + ".png"))
            let data = try TestLabel.rasterJob(raster)
            try data.write(to: directory.appendingPathComponent(name + ".tspl"))
        }
        let lastPage = try document.renderLabel(at: document.pageCount - 1, crop: CGRect(x: 0, y: 0, width: 1, height: 1))
        try lastPage.writePNG(to: directory.appendingPathComponent("letzte-seite.png"))
        print("PDF-Prüfung erfolgreich: \(document.pageCount) Seiten; erste/letzte Seite, Ausschnitt und 90°-Drehung gerendert. Kein Druckauftrag gesendet.")
        exit(0)
    } catch {
        fputs("PDF-Prüfung fehlgeschlagen: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// Independent mode-0 decoder: binary payloads are consumed by length, never by lines.
private func reconstructWireImage(_ job: Data) throws -> MonoRaster {
    let bytes = Array(job)
    var cursor = 0, clears = 0, prints = 0
    var pixels = [UInt8](repeating: 255, count: TestLabel.width * TestLabel.height)
    func fail() -> LabelError { .rendering("Ungueltiger oder unvollstaendiger TSPL-Auftrag.") }
    func newline() throws {
        guard cursor + 2 <= bytes.count, bytes[cursor] == 13, bytes[cursor + 1] == 10 else { throw fail() }
        cursor += 2
    }
    while cursor < bytes.count {
        if bytes[cursor] == 13 { try newline(); continue }
        if bytes[cursor...].starts(with: Array("BITMAP ".utf8)) {
            cursor += 7
            var fields: [Int] = []
            for _ in 0..<5 {
                let start = cursor
                while cursor < bytes.count && bytes[cursor] != 44 { cursor += 1 }
                guard cursor < bytes.count, let value = Int(String(decoding: bytes[start..<cursor], as: UTF8.self)) else { throw fail() }
                fields.append(value); cursor += 1
            }
            let x = fields[0], y = fields[1], stride = fields[2], height = fields[3]
            guard fields[4] == 0, x >= 0, y >= 0, stride > 0, height > 0,
                  x + stride * 8 <= TestLabel.width, y + height <= TestLabel.height,
                  cursor + stride * height <= bytes.count else { throw fail() }
            for row in 0..<height {
                for col in 0..<(stride * 8) {
                    pixels[(y + row) * TestLabel.width + x + col] =
                        bytes[cursor + row * stride + col / 8] & UInt8(0x80 >> (col % 8)) == 0 ? 0 : 255
                }
            }
            cursor += stride * height
            try newline()
        } else {
            let start = cursor
            while cursor < bytes.count && bytes[cursor] != 13 { cursor += 1 }
            let line = String(decoding: bytes[start..<cursor], as: UTF8.self)
            try newline()
            if line == "CLS" { pixels = [UInt8](repeating: 255, count: pixels.count); clears += 1 }
            if line.hasPrefix("BAR ") {
                let fields = line.dropFirst(4).split(separator: ",").compactMap { Int($0) }
                guard fields.count == 4 else { throw fail() }
                let x = fields[0], y = fields[1], width = fields[2], height = fields[3]
                guard x >= 0, y >= 0, width > 0, height > 0,
                      x + width <= TestLabel.width, y + height <= TestLabel.height else { throw fail() }
                for row in y..<(y + height) {
                    for col in x..<(x + width) { pixels[row * TestLabel.width + col] = 0 }
                }
            }
            if line.hasPrefix("PRINT") {
                guard line == "PRINT 1,1" else { throw fail() }
                prints += 1
            }
        }
    }
    guard clears == 1, prints == 1 else { throw fail() }
    var raster = MonoRaster(width: TestLabel.width, height: TestLabel.height)
    for y in 0..<TestLabel.height {
        for x in 0..<TestLabel.width where pixels[y * TestLabel.width + x] == 0 {
            raster.rectangle(x: x, y: y, width: 1, height: 1)
        }
    }
    return raster
}

do {
    let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "output", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let raster = try TestLabel.render()
    try raster.writePNG(to: directory.appendingPathComponent("D520BT-Test-103x199.png"))
    let job = try TestLabel.rasterJob(raster)
    let wireRaster = try reconstructWireImage(job)
    try wireRaster.writePNG(to: directory.appendingPathComponent("D520BT-Test-Wire-103x199.png"))
    try job.write(to: directory.appendingPathComponent("D520BT-Test-103x199.tspl"))
    try TestLabel.connectionJob().write(to: directory.appendingPathComponent("D520BT-Verbindung-103x199.tspl"))
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr, .code128]
    try VNImageRequestHandler(cgImage: wireRaster.cgImage(), options: [:]).perform([request])
    let payloads = (request.results ?? []).compactMap(\.payloadStringValue).sorted()
    let expected = [TestLabel.qrSmall, TestLabel.qrLarge, TestLabel.barcode].sorted()
    let pixelsEqual = wireRaster.pixels == raster.pixels
    let passed = payloads == expected && pixelsEqual
    // The diagnostic negative uses the same header/footer and one full-size BITMAP;
    // polarity does not affect byte count, giving an exact uncompressed reference size.
    var referenceSettings = PrintSettings(); referenceSettings.inverted = true
    let fullJobBytes = try TestLabel.rasterJob(raster, settings: referenceSettings).count
    let report: [String: Any] = [
        "passed": passed, "widthDots": raster.width, "heightDots": raster.height,
        "dotsPerMM": 8, "labelMM": [103, 199], "rasterBytes": raster.packed().count,
        "fullReferenceJobBytes": fullJobBytes, "optimizedJobBytes": job.count,
        "optimizedToFullRatio": Double(job.count) / Double(fullJobBytes),
        "savedBytes": fullJobBytes - job.count, "wirePixelsEqual": pixelsEqual,
        "wirePolarity": "0=black,1=white", "decodedPayloads": payloads, "expectedPayloads": expected,
        "hardwareTested": false, "note": "Neue kompakte Ausgabe nur digital geprueft; erneuter Papiertest ausstehend."
    ]
    let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: directory.appendingPathComponent("validation.json"))
    print(String(decoding: json, as: UTF8.self))
    if !passed { exit(1) }
} catch {
    fputs("Offline-Pruefung fehlgeschlagen: \(error.localizedDescription)\n", stderr)
    exit(1)
}
