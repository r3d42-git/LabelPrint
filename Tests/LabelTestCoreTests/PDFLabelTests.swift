import XCTest
import CoreGraphics
import CoreImage
import Vision
@testable import LabelTestCore

final class PDFLabelTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    }

    /// Independent PDF syntax provides rotation and nonzero box origins without reusing production transforms.
    private func fixture(rotation: Int = 0, origin: CGPoint = .zero, size: CGSize = CGSize(width: 200, height: 300)) throws -> URL {
        let x = origin.x, y = origin.y, w = size.width, h = size.height
        let stream = "0 g \(x) \(y + h / 2) \(w / 2) \(h / 2) re f\n0.4 g \(x + w / 2) \(y + h / 2) \(w / 2) \(h / 2) re f\n0.7 g \(x) \(y) \(w / 2) \(h / 2) re f\n"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(x+w+20) \(y+h+20)] /CropBox [\(x) \(y) \(x+w) \(y+h)] /Rotate \(rotation) /Resources << >> /Contents 4 0 R >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream"
        ]
        return try writePDF(objects: objects)
    }

    private func writePDF(objects: [String]) throws -> URL {
        var pdf = "%PDF-1.4\n", offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index+1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = temporaryURL(); try Data(pdf.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func sample(_ raster: MonoRaster, cropSize: CGSize, x: CGFloat, y: CGFloat) -> UInt8 {
        let scale = min(CGFloat(raster.width - 48) / cropSize.width, CGFloat(raster.height - 48) / cropSize.height)
        let left = (CGFloat(raster.width) - cropSize.width * scale) / 2
        let top = (CGFloat(raster.height) - cropSize.height * scale) / 2
        return raster.pixels[Int(top + y * cropSize.height * scale) * raster.width + Int(left + x * cropSize.width * scale)]
    }

    func testUprightCropPreviewAndClockwiseRotations() throws {
        for pageSize in [CGSize(width: 200, height: 300), CGSize(width: 300, height: 200)] {
            let document = try PDFLabelDocument(url: fixture(size: pageSize))
            XCTAssertEqual(try document.pageSize(at: 0), pageSize)
            let preview = try document.preview(at: 0, maxDimension: 600)
            let bytes = CFDataGetBytePtr(preview.dataProvider!.data!)!
            XCTAssertEqual(bytes[(preview.height / 4) * preview.bytesPerRow + preview.width / 4], 0)
            XCTAssertGreaterThan(bytes[(preview.height * 3 / 4) * preview.bytesPerRow + preview.width * 3 / 4], 240)
            let expectedBlack = [(CGFloat(0.25), CGFloat(0.25)), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)]
            for turns in 0...3 {
                let raster = try document.renderLabel(at: 0, crop: CGRect(x: 0, y: 0, width: 1, height: 1), quarterTurns: turns, threshold: 80)
                let rotated = turns % 2 == 0 ? pageSize : CGSize(width: pageSize.height, height: pageSize.width)
                for point in [(CGFloat(0.25), CGFloat(0.25)), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)] {
                    XCTAssertEqual(sample(raster, cropSize: rotated, x: point.0, y: point.1),
                                   point == expectedBlack[turns] ? 0 : 255, "turn \(turns), \(point)")
                }
                for y in 0..<raster.height {
                    XCTAssertTrue(raster.pixels[(y*raster.width)..<(y*raster.width+24)].allSatisfy { $0 == 255 })
                    XCTAssertTrue(raster.pixels[(y*raster.width+raster.width-24)..<((y+1)*raster.width)].allSatisfy { $0 == 255 })
                }
                XCTAssertTrue(raster.pixels.prefix(24*raster.width).allSatisfy { $0 == 255 })
                XCTAssertTrue(raster.pixels.suffix(24*raster.width).allSatisfy { $0 == 255 })
            }
            let topRight = try document.renderLabel(at: 0, crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), threshold: 160)
            XCTAssertEqual(topRight.pixels[topRight.height / 2 * topRight.width + topRight.width / 2], 0)
            let bottomLeft = try document.renderLabel(at: 0, crop: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), threshold: 160)
            XCTAssertEqual(bottomLeft.pixels[bottomLeft.height / 2 * bottomLeft.width + bottomLeft.width / 2], 255)
        }
    }

    func testIntrinsicRotationAndCropBoxOrigin() throws {
        let document = try PDFLabelDocument(url: fixture(rotation: 90, origin: CGPoint(x: 40, y: 60)))
        XCTAssertEqual(try document.pageSize(at: 0), CGSize(width: 300, height: 200))
        let raster = try document.renderLabel(at: 0, crop: CGRect(x: 0, y: 0, width: 1, height: 1), threshold: 80)
        XCTAssertEqual(sample(raster, cropSize: CGSize(width: 300, height: 200), x: 0.75, y: 0.25), 0)
        XCTAssertEqual(sample(raster, cropSize: CGSize(width: 300, height: 200), x: 0.25, y: 0.25), 255)
        let crop = try document.renderLabel(at: 0, crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), threshold: 80)
        XCTAssertEqual(crop.pixels[crop.width * crop.height / 2 + crop.width / 2], 0)
        let preview = try document.preview(at: 0, maxDimension: 600)
        let bytes = CFDataGetBytePtr(preview.dataProvider!.data!)!
        XCTAssertEqual(bytes[preview.height/4*preview.bytesPerRow+preview.width*3/4], 0)
    }

    func testColoredAsymmetricVectorContentIsNotMirrored() throws {
        let stream = "0 0 1 rg 0 200 100 100 re f\n1 1 0 rg 100 200 100 100 re f\n0 g 140 40 5 60 re f\n140 40 35 5 re f\n"
        let url = try writePDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << >> /Contents 4 0 R >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream"
        ])
        let document = try PDFLabelDocument(url: url)
        let size = CGSize(width: 200, height: 300)
        for turns in 0...3 {
            let raster = try document.renderLabel(at: 0, crop: CGRect(x: 0, y: 0, width: 1, height: 1), quarterTurns: turns)
            let rotated = turns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
            // The L's stem, foot, and white cavity distinguish rotation from reflection.
            for (x, y, ink) in [(0.7125, 0.75, UInt8(0)), (0.8, 0.858, 0), (0.8, 0.75, 255),
                                (0.25, 0.15, 0), (0.75, 0.15, 255)] {
                let point: CGPoint
                switch turns {
                case 1: point = CGPoint(x: 1-y, y: x)
                case 2: point = CGPoint(x: 1-x, y: 1-y)
                case 3: point = CGPoint(x: y, y: 1-x)
                default: point = CGPoint(x: x, y: y)
                }
                XCTAssertEqual(sample(raster, cropSize: rotated, x: point.x, y: point.y), ink)
            }
        }
    }

    func testValidationAndImmutableSnapshot() throws {
        let url = try fixture(), document = try PDFLabelDocument(url: url)
        try Data("changed".utf8).write(to: url)
        XCTAssertEqual(try document.pageSize(at: 0), CGSize(width: 200, height: 300))
        XCTAssertThrowsError(try document.pageSize(at: -1))
        XCTAssertThrowsError(try document.preview(at: 1))
        XCTAssertThrowsError(try document.preview(at: 0, maxDimension: 0))
        XCTAssertThrowsError(try document.preview(at: 0, maxDimension: 9000))
        for crop in [CGRect.zero, CGRect(x: -0.1, y: 0, width: 1, height: 1), CGRect(x: 0.1, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: -1, height: 1)] {
            XCTAssertThrowsError(try document.renderLabel(at: 0, crop: crop))
        }
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertThrowsError(try document.renderLabel(at: 0, crop: full, quarterTurns: -1))
        XCTAssertThrowsError(try document.renderLabel(at: 0, crop: full, quarterTurns: 4))
        for margin in [-1.0, 51.5, Double.infinity, Double.nan] {
            XCTAssertThrowsError(try document.renderLabel(at: 0, crop: full, marginMM: margin))
        }
        XCTAssertThrowsError(try PDFLabelDocument(url: url))
        XCTAssertThrowsError(try PDFLabelDocument(url: temporaryURL()))
        XCTAssertThrowsError(try MonoRaster(width: 0, height: 2, grayscale: [], threshold: 160))
        XCTAssertThrowsError(try MonoRaster(width: 2, height: 2, grayscale: [0], threshold: 160))
        let mono = try MonoRaster(width: 3, height: 1, grayscale: [159,160,161], threshold: 160)
        XCTAssertEqual(mono.pixels, [0,255,255])
    }

    func testSelectedPDFCodesDecodeAtPrinterResolution() throws {
        let url = temporaryURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        var media = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &media, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(media)
        let payload = "LABELPRINT:PDF:SELECTED:CROP"
        let qr = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        qr.setValue(Data(payload.utf8), forKey: "inputMessage")
        qr.setValue("M", forKey: "inputCorrectionLevel")
        let ci = CIContext(options: [.useSoftwareRenderer: true])
        let qrOutput = try XCTUnwrap(qr.outputImage)
        let qrImage = try XCTUnwrap(ci.createCGImage(qrOutput, from: qrOutput.extent))
        let barcode = try XCTUnwrap(CIFilter(name: "CICode128BarcodeGenerator"))
        barcode.setValue(Data("PDF128123".utf8), forKey: "inputMessage")
        barcode.setValue(10, forKey: "inputQuietSpace")
        let barOutput = try XCTUnwrap(barcode.outputImage)
        let barImage = try XCTUnwrap(ci.createCGImage(barOutput, from: barOutput.extent))
        context.interpolationQuality = .none
        context.draw(qrImage, in: CGRect(x: 225, y: 425, width: 150, height: 150))
        context.draw(barImage, in: CGRect(x: 180, y: 240, width: 240, height: 65))
        context.endPDFPage(); context.closePDF()
        let document = try PDFLabelDocument(url: url)
        let raster = try document.renderLabel(at: 0, crop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .code128]
        try VNImageRequestHandler(cgImage: raster.cgImage()).perform([request])
        let decoded = request.results?.compactMap(\.payloadStringValue) ?? []
        XCTAssertTrue(decoded.contains(payload), "Decoded: \(decoded)")
        XCTAssertTrue(decoded.contains("PDF128123"), "Decoded: \(decoded)")
    }

    func testLockedAndEmptyPDFsFailWithFriendlyErrors() throws {
        let url = temporaryURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let metadata = [kCGPDFContextUserPassword: "test-secret", kCGPDFContextOwnerPassword: "owner-secret"] as CFDictionary
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, metadata))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        XCTAssertThrowsError(try PDFLabelDocument(url: url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Passwort"))
        }
        let emptyURL = try writePDF(objects: ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [] /Count 0 >>"])
        XCTAssertThrowsError(try PDFLabelDocument(url: emptyURL))
        let zeroSize = try PDFLabelDocument(url: fixture(size: .zero))
        XCTAssertThrowsError(try zeroSize.pageSize(at: 0))
    }
}
