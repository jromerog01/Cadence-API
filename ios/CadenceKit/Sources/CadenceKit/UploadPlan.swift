import Foundation

public struct UploadPlan: Sendable, Equatable {
    public let sizeBytes: Int64
    public let chunkSize: Int64

    public init(sizeBytes: Int64, chunkSize: Int64) throws {
        guard sizeBytes > 0, chunkSize > 0 else { throw UploadPlanError.invalidSize }
        self.sizeBytes = sizeBytes
        self.chunkSize = chunkSize
    }

    public var totalParts: Int { Int((sizeBytes - 1) / chunkSize + 1) }

    public func range(for part: Int) throws -> Range<Int64> {
        guard (0..<totalParts).contains(part) else { throw UploadPlanError.invalidPart }
        let start = Int64(part) * chunkSize
        return start..<min(start + chunkSize, sizeBytes)
    }

    public func missingParts(received: [Int]) -> [Int] {
        let done = Set(received)
        return (0..<totalParts).filter { !done.contains($0) }
    }
}

public enum UploadPlanError: Error { case invalidSize, invalidPart }
