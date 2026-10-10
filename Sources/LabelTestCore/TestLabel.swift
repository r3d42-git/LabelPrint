import Foundation
import CoreGraphics
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers

public enum LabelError: Error, LocalizedError {
    case rendering(String)
    public var errorDescription: String? {
        switch self { case .rendering(let detail): return detail }
    }
}

/// The nominal 203 dpi head uses 8 physical dots/mm (203.2 dpi).
/// Coordinates are top-to-bottom. `packed` is MSB first with 1 meaning black;
/// D520BT mode-0 wire bytes use the opposite polarity (0 black, 1 white).
public struct MonoRaster {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt8]
    public var bytesPerRow: Int { (width + 7) / 8 }

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0)
        self.width = width; self.height = height
        pixels = [UInt8](repeating: 255, count: width * height)
    }

    public init(width: Int, height: Int, grayscale: [UInt8], threshold: UInt8) throws {
        guard width > 0, height > 0, width <= Int.max / height,
              grayscale.count == width * height else {
            throw LabelError.rendering("Die Rasterabmessungen sind ungültig.")
        }
        self.width = width; self.height = height
        pixels = grayscale.map { $0 < threshold ? 0 : 255 }
    }

    public mutating func rectangle(x: Int, y: Int, width w: Int, height h: Int) {
        guard w > 0, h > 0 else { return }
        for row in max(0, y)..<max(0, min(height, y + h)) {
            for col in max(0, x)..<max(0, min(width, x + w)) {
                pixels[row * width + col] = 0
            }
        }
    }

    public mutating func text(_ value: String, x: Int, y: Int, size: CGFloat = 24) throws {
        let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
        let attributes = [kCTFontAttributeName: font,
                          kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, value as CFString, attributes))
        let textWidth = Int(ceil(CTLineGetTypographicBounds(line, nil, nil, nil))) + 4
        let textHeight = Int(ceil(size * 1.7))
        var gray = [UInt8](repeating: 255, count: textWidth * textHeight)
        try gray.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: textWidth, height: textHeight,
                    bitsPerComponent: 8, bytesPerRow: textWidth, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                throw LabelError.rendering("Text konnte nicht gerendert werden.")
            }
            context.setShouldAntialias(false)
            context.textPosition = CGPoint(x: 0, y: CGFloat(textHeight) - size - 2)
            CTLineDraw(line, context)
        }
        for row in 0..<textHeight where y + row >= 0 && y + row < height {
            for col in 0..<textWidth where x + col >= 0 && x + col < width {
                if gray[row * textWidth + col] < 128 { pixels[(y + row) * width + x + col] = 0 }
            }
        }
    }

    public mutating func code(_ image: CGImage, x: Int, y: Int, scale: Int, barHeight: Int? = nil) throws {
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw LabelError.rendering("Code konnte nicht gerendert werden.")
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        if let barHeight {
            for col in 0..<w where rgba[((h / 2) * w + col) * 4] < 128 {
                rectangle(x: x + col * scale, y: y, width: scale, height: barHeight)
            }
        } else {
            for row in 0..<h {
                for col in 0..<w where rgba[(row * w + col) * 4] < 128 {
                    rectangle(x: x + col * scale, y: y + row * scale, width: scale, height: scale)
                }
            }
        }
    }

    public func packed(inverted: Bool = false) -> Data {
        var bytes = [UInt8](repeating: inverted ? 255 : 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] == 0 {
                bytes[y * bytesPerRow + x / 8] ^= UInt8(0x80 >> (x % 8))
            }
        }
        return Data(bytes)
    }

    public func cgImage() throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw LabelError.rendering("Vorschaubild konnte nicht erstellt werden.")
        }
        return image
    }

    public func writePNG(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw LabelError.rendering("PNG-Datei konnte nicht angelegt werden.")
        }
        CGImageDestinationAddImage(destination, try cgImage(), [kCGImagePropertyDPIWidth: 203.2, kCGImagePropertyDPIHeight: 203.2] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LabelError.rendering("PNG konnte nicht gespeichert werden.") }
    }
}

public struct PrintSettings: Equatable {
    public var density: Int = 12
    public var speed: Int = 3
    public var gapMM: Int = 3
    public var inverted: Bool = false
    public init() {}
}

public enum TestLabel {
    public static let width = 824
    public static let height = 1592
    public static let qrSmall = "LABELPRINT:D520BT:103x199:Q4"
    public static let qrLarge = "LABELPRINT:D520BT:103x199:Q6"
    public static let barcode = "LP520199"

    private static func codeImage(name: String, payload: String) throws -> CGImage {
        guard let filter = CIFilter(name: name) else { throw LabelError.rendering("Code-Generator fehlt: \(name)") }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        if name == "CIQRCodeGenerator" { filter.setValue("M", forKey: "inputCorrectionLevel") }
        else { filter.setValue(10, forKey: "inputQuietSpace") }
        guard let output = filter.outputImage,
              let image = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent) else {
            throw LabelError.rendering("Code konnte nicht erzeugt werden.")
        }
        return image
    }

    public static func render(settings: PrintSettings = PrintSettings()) throws -> MonoRaster {
        var raster = MonoRaster(width: width, height: height)
        raster.rectangle(x: 24, y: 24, width: width - 48, height: 2)
        raster.rectangle(x: 24, y: height - 26, width: width - 48, height: 2)
        raster.rectangle(x: 24, y: 24, width: 2, height: height - 48)
        raster.rectangle(x: width - 26, y: 24, width: 2, height: height - 48)
        try raster.text("D520BT / DRUCKTEST", x: 64, y: 58, size: 34)
        try raster.text("103 x 199 mm | 8 Punkte/mm", x: 64, y: 116, size: 24)
        try raster.text("Dichte \(settings.density) | Tempo \(settings.speed) | Luecke \(settings.gapMM) mm", x: 64, y: 157, size: 20)
        try raster.text("QR-CODES: BEIDE SCANNEN", x: 64, y: 228, size: 25)
        try raster.code(codeImage(name: "CIQRCodeGenerator", payload: qrSmall), x: 96, y: 310, scale: 4)
        try raster.code(codeImage(name: "CIQRCodeGenerator", payload: qrLarge), x: 438, y: 290, scale: 6)
        try raster.text("4 Punkte/Modul", x: 64, y: 515, size: 21)
        try raster.text("6 Punkte/Modul", x: 425, y: 515, size: 21)
        try raster.text("Inhalt: LABELPRINT:D520BT:103x199:Q4 / Q6", x: 64, y: 565, size: 17)
        try raster.text("CODE 128", x: 64, y: 646, size: 25)
        let code = try codeImage(name: "CICode128BarcodeGenerator", payload: barcode)
        let scale = 3
        try raster.code(code, x: (width - code.width * scale) / 2, y: 713, scale: scale, barHeight: 136)
        try raster.text(barcode, x: 64, y: 876, size: 28)
        try raster.text("LINIEN: 1 / 2 / 3 / 4 PUNKTE", x: 64, y: 974, size: 22)
        for thickness in 1...4 {
            let x = 80 + (thickness - 1) * 175
            for i in 0..<12 { raster.rectangle(x: x + i * thickness * 2, y: 1040, width: thickness, height: 96) }
            try raster.text("\(thickness)", x: x, y: 1150, size: 21)
        }
        try raster.text("MESSSTRECKE: 50 mm", x: 64, y: 1240, size: 24)
        raster.rectangle(x: 80, y: 1310, width: 400, height: 2)
        for i in 0...10 {
            raster.rectangle(x: 80 + i * 40, y: 1300, width: 2, height: i % 2 == 0 ? 28 : 18)
        }
        try raster.text("Pruefen: lesbar, keine weissen Streifen,", x: 64, y: 1398, size: 18)
        try raster.text("Codes scannbar, Messstrecke korrekt.", x: 64, y: 1430, size: 18)
        try raster.text("LabelPrint / lokaler Test / 1 Etikett", x: 64, y: 1490, size: 18)
        return raster
    }

    private static func header(settings: PrintSettings) throws -> String {
        guard (0...15).contains(settings.density), (2...5).contains(settings.speed), (0...9).contains(settings.gapMM) else {
            throw LabelError.rendering("Ungueltige Druckeinstellungen.")
        }
        return "\r\nSIZE 103 mm,199 mm\r\nGAP \(settings.gapMM) mm,0 mm\r\nDENSITY \(settings.density)\r\nSPEED \(settings.speed)\r\nDIRECTION 1,0\r\nREFERENCE 0,0\r\nOFFSET 0 mm\r\nCLS\r\n"
    }

    /// First use: a tiny native command job establishes command parsing before raster transfer.
    public static func connectionJob(settings: PrintSettings = PrintSettings()) throws -> Data {
        let commands = try header(settings: settings) + "BOX 40,40,784,1552,3\r\nTEXT 80,100,\"3\",0,2,2,\"D520BT TEST\"\r\nTEXT 80,180,\"3\",0,1,1,\"103 x 199 mm\"\r\nBAR 80,300,400,3\r\nBAR 80,285,3,33\r\nBAR 480,285,3,33\r\nTEXT 80,345,\"3\",0,1,1,\"50 mm\"\r\nPRINT 1,1\r\n"
        return Data(commands.utf8)
    }

    /// Sparse, disjoint tiles retain the exact raster using verified BAR and mode-0 BITMAP.
    /// CLS supplies white space, including code quiet zones. Byte padding stays within each
    /// tile and is white on the wire, so it cannot erase a neighbouring tile's ink.
    public static func rasterJob(_ raster: MonoRaster, settings: PrintSettings = PrintSettings()) throws -> Data {
        guard raster.width == width, raster.height == height else { throw LabelError.rendering("Das Testbild muss 824 x 1592 Punkte haben.") }
        var job = Data(try header(settings: settings).utf8)
        if settings.inverted {
            // A global negative includes otherwise empty space; sparse omission cannot express it.
            job.append(Data("BITMAP 0,0,\(raster.bytesPerRow),\(raster.height),0,".utf8))
            job.append(raster.packed())
            job.append(Data("\r\n".utf8))
        } else {
            for tileY in stride(from: 0, to: raster.height, by: 32) {
                for tileX in stride(from: 0, to: raster.width, by: 64) {
                    let endX = min(tileX + 64, raster.width)
                    let endY = min(tileY + 32, raster.height)
                    var minX = endX, minY = endY, maxX = tileX - 1, maxY = tileY - 1
                    var blackCount = 0
                    for y in tileY..<endY {
                        for x in tileX..<endX where raster.pixels[y * raster.width + x] == 0 {
                            minX = min(minX, x); maxX = max(maxX, x)
                            minY = min(minY, y); maxY = max(maxY, y)
                            blackCount += 1
                        }
                    }
                    guard blackCount > 0 else { continue }
                    let cropWidth = maxX - minX + 1, cropHeight = maxY - minY + 1
                    if blackCount == cropWidth * cropHeight {
                        job.append(Data("BAR \(minX),\(minY),\(cropWidth),\(cropHeight)\r\n".utf8))
                    } else {
                        // Align the left edge down to a byte within this tile. The padded right
                        // edge is at most endX because both tile boundaries are byte aligned.
                        let byteX = minX / 8 * 8
                        let rowBytes = (maxX - byteX + 8) / 8
                        var payload = [UInt8](repeating: 255, count: rowBytes * cropHeight)
                        for y in minY...maxY {
                            for x in minX...maxX where raster.pixels[y * raster.width + x] == 0 {
                                payload[(y - minY) * rowBytes + (x - byteX) / 8] &= ~UInt8(0x80 >> ((x - byteX) % 8))
                            }
                        }
                        job.append(Data("BITMAP \(byteX),\(minY),\(rowBytes),\(cropHeight),0,".utf8))
                        job.append(contentsOf: payload)
                        job.append(Data("\r\n".utf8))
                    }
                }
            }
        }
        job.append(Data("PRINT 1,1\r\n".utf8))
        return job
    }
}
