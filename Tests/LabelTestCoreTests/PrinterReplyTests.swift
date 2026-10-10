import XCTest
@testable import LabelTestCore

final class PrinterReplyTests: XCTestCase {
    func testFragmentedAndCombinedReplies() {
        var parser = PrinterReplyParser()
        XCTAssertEqual(parser.consume(Data("SSSGETPRI".utf8)), [])
        XCTAssertEqual(parser.consume(Data("NTING:DOING\r".utf8)), [.printing])
        XCTAssertEqual(parser.consume(Data("\nSSSGETPRINTING:DONE\r\n".utf8)), [.done])
        XCTAssertEqual(parser.consume(Data("SSSGETPRINTING:DOING\r\nSSSGETPRINTING:DONE\r\n".utf8)), [.printing, .done])
    }

    func testUnknownStatusDoesNotMeanSuccess() {
        var parser = PrinterReplyParser()
        XCTAssertEqual(parser.consume(Data([0x7E, 1, 0x7E, 13, 10])), [])
        XCTAssertEqual(parser.consume(Data("SSSGETPRINTING:UNKNOWN\r\nDONE\r\n".utf8)), [])
        XCTAssertEqual(parser.consume(Data(repeating: 65, count: 2000)), [])
        XCTAssertEqual(parser.consume(Data("\r\nSSSGETPRINTING:DONE\r\n".utf8)), [.done])
    }
}
