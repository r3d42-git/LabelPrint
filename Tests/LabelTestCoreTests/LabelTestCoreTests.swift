import XCTest
@testable import LabelTestCore

final class LabelTestCoreTests: XCTestCase {
    func testPackingIsMSBFirstWithWhiteRowPadding() {
        var raster = MonoRaster(width: 10, height: 2)
        raster.rectangle(x: 0, y: 0, width: 1, height: 1)
        raster.rectangle(x: 7, y: 0, width: 2, height: 1)
        raster.rectangle(x: 9, y: 1, width: 1, height: 1)
        XCTAssertEqual(Array(raster.packed()), [0x81, 0x80, 0x00, 0x40])
        XCTAssertEqual(Array(raster.packed(inverted: true)), [0x7E, 0x7F, 0xFF, 0xBF])
    }

    /// Read BITMAP binary by its declared byte count; embedded CR/LF are ordinary pixels.
    private func reconstruct(_ job: Data) throws -> (pixels: [UInt8], bitmaps: Int, bars: Int) {
        let bytes = Array(job)
        var cursor = 0, prints = 0, clears = 0, bitmaps = 0, bars = 0
        var pixels = [UInt8](repeating: 255, count: TestLabel.width * TestLabel.height)
        func consume(_ literal: String) throws {
            let expected = Array(literal.utf8)
            XCTAssertEqual(Array(bytes[cursor..<min(cursor + expected.count, bytes.count)]), expected)
            guard cursor + expected.count <= bytes.count else { throw LabelError.rendering("Truncated TSPL") }
            cursor += expected.count
        }
        while cursor < bytes.count {
            if bytes[cursor] == 13 { try consume("\r\n"); continue }
            if bytes[cursor...].starts(with: Array("BITMAP ".utf8)) {
                try consume("BITMAP ")
                var fields: [Int] = []
                for _ in 0..<5 {
                    let start = cursor
                    while cursor < bytes.count && bytes[cursor] != 44 { cursor += 1 }
                    guard cursor < bytes.count,
                          let value = Int(String(decoding: bytes[start..<cursor], as: UTF8.self)) else {
                        throw LabelError.rendering("Malformed BITMAP")
                    }
                    fields.append(value); cursor += 1
                }
                let x = fields[0], y = fields[1], stride = fields[2], height = fields[3]
                XCTAssertEqual(fields[4], 0)
                guard x >= 0, y >= 0, stride > 0, height > 0,
                      x + stride * 8 <= TestLabel.width, y + height <= TestLabel.height,
                      cursor + stride * height <= bytes.count else { throw LabelError.rendering("Bitmap out of bounds") }
                for row in 0..<height {
                    for col in 0..<(stride * 8) {
                        let byte = bytes[cursor + row * stride + col / 8]
                        pixels[(y + row) * TestLabel.width + x + col] = byte & UInt8(0x80 >> (col % 8)) == 0 ? 0 : 255
                    }
                }
                cursor += stride * height
                try consume("\r\n")
                bitmaps += 1
            } else {
                let start = cursor
                while cursor < bytes.count && bytes[cursor] != 13 { cursor += 1 }
                let line = String(decoding: bytes[start..<cursor], as: UTF8.self)
                try consume("\r\n")
                if line == "CLS" { pixels = [UInt8](repeating: 255, count: pixels.count); clears += 1 }
                if line.hasPrefix("BAR ") {
                    let values = line.dropFirst(4).split(separator: ",").compactMap { Int($0) }
                    guard values.count == 4 else { throw LabelError.rendering("Malformed BAR") }
                    let x = values[0], y = values[1], width = values[2], height = values[3]
                    guard x >= 0, y >= 0, width > 0, height > 0,
                          x + width <= TestLabel.width, y + height <= TestLabel.height else {
                        throw LabelError.rendering("Bar out of bounds")
                    }
                    for row in y..<(y + height) {
                        for col in x..<(x + width) { pixels[row * TestLabel.width + col] = 0 }
                    }
                    bars += 1
                }
                if line.hasPrefix("PRINT") { XCTAssertEqual(line, "PRINT 1,1"); prints += 1 }
            }
        }
        XCTAssertEqual(prints, 1); XCTAssertEqual(clears, 1)
        return (pixels, bitmaps, bars)
    }

    func testPhysicalSizeLosslessWireImageAndSinglePrint() throws {
        let raster = try TestLabel.render()
        XCTAssertEqual(raster.width, 103 * 8)
        XCTAssertEqual(raster.height, 199 * 8)
        XCTAssertEqual(raster.packed().count, 103 * 1592)
        let job = try TestLabel.rasterJob(raster)
        let result = try reconstruct(job)
        XCTAssertEqual(result.pixels, raster.pixels)
        XCTAssertGreaterThan(result.bitmaps, 0)
        XCTAssertGreaterThan(result.bars, 0)
        XCTAssertLessThan(job.count, raster.packed().count / 2)
        XCTAssertTrue(String(decoding: job.prefix(100), as: UTF8.self).contains("SIZE 103 mm,199 mm\r\n"))
        XCTAssertLessThan(Double(raster.pixels.filter { $0 == 0 }.count) / Double(raster.pixels.count), 0.25)
        XCTAssertEqual(Set(raster.pixels), Set([UInt8(0), UInt8(255)]))
    }

    func testSparseTilesAndPaddingAcrossEdgesAreLossless() throws {
        var raster = MonoRaster(width: TestLabel.width, height: TestLabel.height)
        for (x, y, w, h) in [(0, 0, 1, 1), (63, 31, 3, 3), (127, 63, 2, 3),
                              (819, 1589, 5, 3), (65, 35, 7, 5), (77, 39, 1, 1),
                              (57, 1, 1, 1), (64, 1, 1, 1)] {
            raster.rectangle(x: x, y: y, width: w, height: h)
        }
        // Force payload bytes containing TSPL-like text and delimiters, plus a mixed tile.
        let embedded = Array("\r\nPRINT 1,1\r\n".utf8)
        for (row, byte) in embedded.enumerated() {
            for bit in 0..<8 where byte & UInt8(0x80 >> bit) == 0 {
                raster.rectangle(x: 200 + bit, y: 100 + row, width: 1, height: 1)
            }
        }
        let result = try reconstruct(TestLabel.rasterJob(raster))
        XCTAssertEqual(result.pixels, raster.pixels)
        XCTAssertGreaterThan(result.bitmaps, 0); XCTAssertGreaterThan(result.bars, 0)
    }

    func testBlankSolidAndGlobalNegative() throws {
        var raster = MonoRaster(width: TestLabel.width, height: TestLabel.height)
        let blank = try reconstruct(TestLabel.rasterJob(raster))
        XCTAssertEqual(blank.pixels, raster.pixels)
        XCTAssertEqual(blank.bitmaps + blank.bars, 0)
        raster.rectangle(x: 0, y: 0, width: raster.width, height: raster.height)
        let solid = try reconstruct(TestLabel.rasterJob(raster))
        XCTAssertEqual(solid.pixels, raster.pixels)
        XCTAssertEqual(solid.bitmaps, 0)
        raster = try TestLabel.render()
        var settings = PrintSettings(); settings.inverted = true
        let negative = try reconstruct(TestLabel.rasterJob(raster, settings: settings))
        XCTAssertEqual(negative.pixels, raster.pixels.map { 255 - $0 })
        XCTAssertEqual(negative.bitmaps, 1); XCTAssertEqual(negative.bars, 0)
    }

    func testInvalidSettingsRejectedBeforeSending() throws {
        var settings = PrintSettings()
        settings.density = 16
        XCTAssertThrowsError(try TestLabel.connectionJob(settings: settings))
        settings.density = 12; settings.gapMM = -1
        XCTAssertThrowsError(try TestLabel.connectionJob(settings: settings))
        settings.gapMM = 3; settings.speed = 0
        XCTAssertThrowsError(try TestLabel.connectionJob(settings: settings))
        XCTAssertThrowsError(try TestLabel.rasterJob(MonoRaster(width: 100, height: 100)))
    }
}
