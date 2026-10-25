import Foundation

public struct InboxItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let filename: String
    public let storedFilename: String
    public let model: String
    public let language: String?

    public func fileURL(in root: URL) -> URL { root.appending(path: storedFilename) }
}

public struct Inbox: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public func enqueue(source: URL, filename: String, model: String, language: String?) throws -> InboxItem {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let ext = URL(fileURLWithPath: filename).pathExtension
        let storedFilename = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
        let destination = root.appending(path: storedFilename)
        try FileManager.default.copyItem(at: source, to: destination)
        let item = InboxItem(id: id, filename: filename, storedFilename: storedFilename, model: model, language: language)
        do {
            let data = try JSONEncoder().encode(item)
            try data.write(to: root.appending(path: "\(id.uuidString).json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return item
    }

    public func pending() throws -> [InboxItem] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(InboxItem.self, from: Data(contentsOf: $0)) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func remove(_ item: InboxItem) throws {
        try FileManager.default.removeItem(at: root.appending(path: "\(item.id.uuidString).json"))
        try FileManager.default.removeItem(at: item.fileURL(in: root))
    }
}
