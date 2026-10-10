import SwiftUI
import AppKit
import LabelTestCore

struct PDFCropCanvas: NSViewRepresentable {
    let image: NSImage
    let selection: CGRect
    let enabled: Bool
    let onSelect: (CGRect) -> Void

    func makeNSView(context: Context) -> CropCanvasView { CropCanvasView() }
    func updateNSView(_ view: CropCanvasView, context: Context) {
        view.image = image; view.selection = selection; view.isEnabled = enabled
        view.onSelect = onSelect; view.needsDisplay = true
    }
}

final class CropCanvasView: NSView {
    var image: NSImage?
    var selection = CGRect(x: 0, y: 0, width: 1, height: 1)
    var onSelect: ((CGRect) -> Void)?
    var isEnabled = true
    private var anchor: CGPoint?
    private var draft: CGRect?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("PDF-Seite: Mit der Maus einen rechteckigen Druckbereich aufziehen")
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var pageRect: CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let area = bounds.insetBy(dx: 18, dy: 18)
        let factor = min(area.width / image.size.width, area.height / image.size.height)
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        guard let image else { return }
        let page = pageRect
        NSColor.white.setFill(); page.fill()
        image.draw(in: page, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
        NSColor.separatorColor.setStroke(); NSBezierPath(rect: page).stroke()
        let crop = draft ?? selection
        let selected = CGRect(x: page.minX + crop.minX * page.width, y: page.minY + crop.minY * page.height,
                              width: crop.width * page.width, height: crop.height * page.height)
        NSColor.black.withAlphaComponent(0.25).setFill()
        CGRect(x: page.minX, y: page.minY, width: page.width, height: max(0, selected.minY - page.minY)).fill()
        CGRect(x: page.minX, y: selected.maxY, width: page.width, height: max(0, page.maxY - selected.maxY)).fill()
        CGRect(x: page.minX, y: selected.minY, width: max(0, selected.minX - page.minX), height: selected.height).fill()
        CGRect(x: selected.maxX, y: selected.minY, width: max(0, page.maxX - selected.maxX), height: selected.height).fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: selected); outline.lineWidth = 2
        outline.stroke()
    }

    override func resetCursorRects() { if isEnabled { addCursorRect(pageRect, cursor: .crosshair) } }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard pageRect.contains(point) else { return }
        window?.makeFirstResponder(self)
        anchor = point; draft = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, let anchor else { return }
        draft = PDFCropGeometry.selection(from: anchor, to: convert(event.locationInWindow, from: nil), in: pageRect)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil; draft = nil; needsDisplay = true }
        guard isEnabled, let anchor,
              let rect = PDFCropGeometry.selection(from: anchor, to: convert(event.locationInWindow, from: nil), in: pageRect),
              rect.width * pageRect.width >= 4, rect.height * pageRect.height >= 4 else { return }
        selection = rect; onSelect?(rect)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { anchor = nil; draft = nil; needsDisplay = true }
        else { super.keyDown(with: event) }
    }
}
