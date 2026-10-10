import Foundation

/// Reassembles the CR/LF status lines observed from the user's D520 over BLE.
/// Unknown lines and binary ACK frames never become a successful-print assertion.
public struct PrinterReplyParser {
    public enum PrintingState: Equatable { case printing, done }
    private var line = Data()
    public init() {}

    public mutating func consume(_ bytes: Data) -> [PrintingState] {
        var results: [PrintingState] = []
        for byte in bytes {
            if byte == 10 || byte == 13 {
                let text = String(decoding: line, as: UTF8.self)
                if text == "SSSGETPRINTING:DOING" { results.append(.printing) }
                if text == "SSSGETPRINTING:DONE" { results.append(.done) }
                line.removeAll(keepingCapacity: true)
            } else {
                if line.count >= 512 { line.removeAll(keepingCapacity: true) }
                line.append(byte)
            }
        }
        return results
    }
}
