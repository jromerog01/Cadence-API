import Foundation
import Testing
@testable import CadenceKit

@Test func inboxCopiesWithoutLoadingAudio() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".m4a")
    defer { try? FileManager.default.removeItem(at: source) }
    try Data(repeating: 7, count: 128).write(to: source)
    let inbox = Inbox(root: root)
    let item = try inbox.enqueue(source: source, filename: "reunión.m4a", model: "small", language: "es")
    #expect(try inbox.pending() == [item])
    #expect(try Data(contentsOf: item.fileURL(in: root)).count == 128)
    try inbox.remove(item)
    #expect(try inbox.pending().isEmpty)
}
