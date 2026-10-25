import Testing
@testable import CadenceKit

@Test func uploadChunkMathAndResume() throws {
    let plan = try UploadPlan(sizeBytes: 17, chunkSize: 8)
    #expect(plan.totalParts == 3)
    #expect(try plan.range(for: 0) == 0..<8)
    #expect(try plan.range(for: 2) == 16..<17)
    #expect(plan.missingParts(received: [2, 0]) == [1])
    #expect(throws: UploadPlanError.self) { try plan.range(for: 3) }
}
