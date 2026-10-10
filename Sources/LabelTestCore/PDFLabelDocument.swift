import Foundation
import CoreGraphics

/// Local immutable PDF snapshot. All access to the Core Graphics document is serialized.
/// Crops use normalized upright page coordinates, with their origin at the top left.
public final class PDFLabelDocument: @unchecked Sendable {
    private let provider: CGDataProvider
    private let document: CGPDFDocument
    private let lock = NSLock()
    public let pageCount: Int

    public init(url: URL) throws {
        let bytes: Data
        do { bytes = try Data(contentsOf: url) }
        catch { throw LabelError.rendering("Die PDF-Datei konnte nicht gelesen werden.") }
        guard let provider = CGDataProvider(data: bytes as CFData),
              let document = CGPDFDocument(provider) else {
            throw LabelError.rendering("Die Datei ist keine lesbare PDF-Datei.")
        }
        guard !document.isEncrypted || document.isUnlocked else {
            throw LabelError.rendering("Die PDF-Datei ist durch ein Passwort geschützt. Bitte zuerst eine entsperrte Kopie bereitstellen.")
        }
        guard document.numberOfPages > 0 else {
            throw LabelError.rendering("Die PDF-Datei enthält keine Seiten.")
        }
        self.provider = provider
        self.document = document
        pageCount = document.numberOfPages
    }

    private func page(_ index: Int) throws -> CGPDFPage {
        guard index >= 0, index < pageCount, let page = document.page(at: index + 1) else {
            throw LabelError.rendering("Die gewählte PDF-Seite ist nicht vorhanden.")
        }
        return page
    }

    private func size(_ page: CGPDFPage) throws -> CGSize {
        let box = page.getBoxRect(.cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else {
            throw LabelError.rendering("Die PDF-Seite hat ungültige Abmessungen.")
        }
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        return rotation == 90 || rotation == 270
            ? CGSize(width: box.height, height: box.width) : box.size
    }

    public func pageSize(at index: Int) throws -> CGSize {
        lock.lock(); defer { lock.unlock() }
        return try size(page(index))
    }

    public func preview(at index: Int, maxDimension: Int = 1800) throws -> CGImage {
        lock.lock(); defer { lock.unlock() }
        guard (1...8192).contains(maxDimension) else {
            throw LabelError.rendering("Die Größe der PDF-Vorschau ist ungültig (1 bis 8192 Punkte).")
        }
        let page = try page(index), pageSize = try size(page)
        let scale = CGFloat(maxDimension) / max(pageSize.width, pageSize.height)
        let width = max(1, Int((pageSize.width * scale).rounded()))
        let height = max(1, Int((pageSize.height * scale).rounded()))
        return try draw(page, pageSize: pageSize, crop: CGRect(origin: .zero, size: pageSize),
                        turns: 0, width: width, height: height, margin: 0).image
    }

    public func renderLabel(at index: Int, crop: CGRect, quarterTurns: Int = 0,
                            threshold: UInt8 = 160, marginMM: Double = 3) throws -> MonoRaster {
        lock.lock(); defer { lock.unlock() }
        guard (0...3).contains(quarterTurns) else {
            throw LabelError.rendering("Die Drehung muss zwischen 0 und 3 Vierteldrehungen liegen.")
        }
        guard marginMM.isFinite, marginMM >= 0, marginMM * 16 < Double(TestLabel.width) else {
            throw LabelError.rendering("Der weiße Rand ist für das Etikett zu groß oder ungültig.")
        }
        guard crop.origin.x.isFinite, crop.origin.y.isFinite, crop.width.isFinite, crop.height.isFinite,
              crop.width > 0, crop.height > 0, crop.minX >= 0, crop.minY >= 0,
              crop.maxX <= 1, crop.maxY <= 1 else {
            throw LabelError.rendering("Bitte einen Ausschnitt innerhalb der PDF-Seite auswählen.")
        }
        let page = try page(index), pageSize = try size(page)
        let selection = CGRect(x: crop.minX * pageSize.width, y: crop.minY * pageSize.height,
                               width: crop.width * pageSize.width, height: crop.height * pageSize.height)
        guard selection.width > 0, selection.height > 0 else {
            throw LabelError.rendering("Der PDF-Ausschnitt ist zu klein zum Rendern.")
        }
        let result = try draw(page, pageSize: pageSize, crop: selection, turns: quarterTurns,
                              width: TestLabel.width, height: TestLabel.height, margin: CGFloat(marginMM * 8))
        return try MonoRaster(width: TestLabel.width, height: TestLabel.height,
                              grayscale: result.gray, threshold: threshold)
    }

    private func draw(_ page: CGPDFPage, pageSize: CGSize, crop: CGRect, turns: Int,
                      width: Int, height: Int, margin: CGFloat) throws -> (image: CGImage, gray: [UInt8]) {
        var gray = [UInt8](repeating: 255, count: width * height)
        let image = try gray.withUnsafeMutableBytes { bytes -> CGImage in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                throw LabelError.rendering("Die PDF-Seite konnte nicht gerendert werden.")
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Bitmap rows are stored top-to-bottom, while the default CGContext uses bottom-left.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            let rotated = turns % 2 == 0 ? crop.size : CGSize(width: crop.height, height: crop.width)
            let scale = min((CGFloat(width) - margin * 2) / rotated.width,
                            (CGFloat(height) - margin * 2) / rotated.height)
            guard scale.isFinite, scale > 0 else {
                throw LabelError.rendering("Der PDF-Ausschnitt hat ungültige Abmessungen.")
            }
            let destination = CGRect(x: (CGFloat(width) - rotated.width * scale) / 2,
                                     y: (CGFloat(height) - rotated.height * scale) / 2,
                                     width: rotated.width * scale, height: rotated.height * scale)
            context.clip(to: destination)
            context.translateBy(x: destination.minX, y: destination.minY)
            context.scaleBy(x: scale, y: scale)
            // Clockwise turns in top-left coordinates, keeping the rotated crop in positive space.
            switch turns {
            case 1: context.translateBy(x: crop.height, y: 0); context.rotate(by: .pi / 2)
            case 2: context.translateBy(x: crop.width, y: crop.height); context.rotate(by: .pi)
            case 3: context.translateBy(x: 0, y: crop.width); context.rotate(by: -.pi / 2)
            default: break
            }
            context.translateBy(x: -crop.minX, y: -crop.minY)
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            context.concatenate(page.getDrawingTransform(.cropBox,
                rect: CGRect(origin: .zero, size: pageSize), rotate: 0, preserveAspectRatio: true))
            context.interpolationQuality = .high
            context.drawPDFPage(page)
            guard let image = context.makeImage() else {
                throw LabelError.rendering("Das PDF-Raster konnte nicht erstellt werden.")
            }
            return image
        }
        return (image, gray)
    }
}
