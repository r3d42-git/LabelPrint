import Foundation

public enum PDFCropGeometry {
    /// Input and normalized output both use the displayed page's top-left origin.
    public static func selection(from start: CGPoint, to end: CGPoint, in page: CGRect) -> CGRect? {
        guard page.width > 0, page.height > 0,
              [start.x, start.y, end.x, end.y, page.minX, page.minY, page.width, page.height].allSatisfy({ $0.isFinite }) else { return nil }
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(page.maxX, max(page.minX, point.x)), y: min(page.maxY, max(page.minY, point.y)))
        }
        let a = clamp(start), b = clamp(end)
        guard a.x != b.x, a.y != b.y else { return nil }
        let left = max(0, min(1, (min(a.x, b.x) - page.minX) / page.width))
        let top = max(0, min(1, (min(a.y, b.y) - page.minY) / page.height))
        let right = max(0, min(1, (max(a.x, b.x) - page.minX) / page.width))
        let bottom = max(0, min(1, (max(a.y, b.y) - page.minY) / page.height))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
