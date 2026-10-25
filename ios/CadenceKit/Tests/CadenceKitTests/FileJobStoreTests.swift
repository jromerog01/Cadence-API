import Foundation
import Testing
@testable import CadenceKit

@Test func persistsTranscriptAndResumeCheckpoint() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = StoredJob(job: Job(originalFilename: "reunión.m4a", model: "apple-speech"),
                           origin: .device, resumeSeconds: 10.5)
    let store = FileJobStore(root: root)
    try await store.save(record)
    let restored = try await FileJobStore(root: root).load(record.job.id)
    #expect(restored?.resumeSeconds == 10.5)
    #expect(restored?.job.originalFilename == record.job.originalFilename)
    try await store.delete(record.job.id)
    #expect(try await store.all().isEmpty)
}
