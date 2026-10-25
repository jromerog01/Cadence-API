import Foundation

public enum JobOrigin: String, Codable, Sendable { case server, device }

public struct StoredJob: Codable, Sendable, Equatable {
    public var job: Job
    public var origin: JobOrigin
    public var audioPath: String?
    public var serverId: String?
    public var resumeSeconds: Double

    public init(job: Job, origin: JobOrigin, audioPath: String? = nil,
                serverId: String? = nil, resumeSeconds: Double = 0) {
        self.job = job; self.origin = origin; self.audioPath = audioPath
        self.serverId = serverId; self.resumeSeconds = resumeSeconds
    }
}

public actor FileJobStore {
    public let root: URL

    public init(root: URL) { self.root = root }

    private func url(_ id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id) else { throw CocoaError(.fileWriteInvalidFileName) }
        return root.appending(path: uuid.uuidString + ".json")
    }

    public func save(_ record: StoredJob) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = APIJSON.encoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: url(record.job.id), options: .atomic)
    }

    public func load(_ id: String) throws -> StoredJob? {
        let file = try url(id)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try APIJSON.decoder().decode(StoredJob.self, from: Data(contentsOf: file))
    }

    public func all() throws -> [StoredJob] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try APIJSON.decoder().decode(StoredJob.self, from: Data(contentsOf: $0)) }
            .sorted { $0.job.createdAt > $1.job.createdAt }
    }

    public func delete(_ id: String) throws {
        let file = try url(id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
