import XCTest
@testable import LabelTestCore

final class PDFCropGeometryTests: XCTestCase {
    func testReverseDragHasSameNormalizedSelection() {
        let page = CGRect(x: 20, y: 40, width: 200, height: 400)
        let a = CGPoint(x: 70, y: 140), b = CGPoint(x: 170, y: 340)
        XCTAssertEqual(PDFCropGeometry.selection(from: a, to: b, in: page), CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertEqual(PDFCropGeometry.selection(from: b, to: a, in: page), PDFCropGeometry.selection(from: a, to: b, in: page))
    }
    func testOutsideDragClipsAndClicksAreIgnored() {
        let page = CGRect(x: 20, y: 40, width: 200, height: 400)
        XCTAssertEqual(PDFCropGeometry.selection(from: .zero, to: CGPoint(x: 1000, y: 1000), in: page), CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertNil(PDFCropGeometry.selection(from: .zero, to: .zero, in: page))
        XCTAssertNil(PDFCropGeometry.selection(from: .zero, to: CGPoint(x: 2, y: 3), in: .zero))
    }
}
