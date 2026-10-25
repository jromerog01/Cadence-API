import Foundation

public struct SSEMessage: Sendable, Equatable {
    public let event: String
    public let data: String
}

public struct SSEParser: Sendable {
    private var buffer = ""
    private var event = "message"
    private var data: [String] = []

    public init() {}

    public mutating func feed(_ chunk: String) -> [SSEMessage] {
        buffer += chunk
        buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")
        var result: [SSEMessage] = []
        while let end = buffer.firstIndex(of: "\n") {
            var line = String(buffer[..<end])
            buffer = String(buffer[buffer.index(after: end)...])
            if line.hasSuffix("\r") { line.removeLast() }
            if line.isEmpty {
                if !data.isEmpty { result.append(SSEMessage(event: event, data: data.joined(separator: "\n"))) }
                event = "message"
                data.removeAll()
            } else if !line.hasPrefix(":") {
                let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let value = pieces.count > 1 ? String(pieces[1]).replacingOccurrences(of: "^ ", with: "", options: .regularExpression) : ""
                if pieces[0] == "event" { event = value }
                if pieces[0] == "data" { data.append(value) }
            }
        }
        return result
    }
}
