import Foundation
import Testing
@testable import CadenceKit

@Test func decodesBackendModelsAndDates() throws {
    let json = """
    {"id":"7ea01d35-27f5-4d81-a33d-096b579ddaa7","original_filename":"reunión.m4a",\
    "duration_seconds":63.25,"model":"small","language":null,"detected_language":"es",\
    "status":"done","progress":1.0,"stage":null,"error_message":null,"word_count":2,\
    "created_at":"2026-10-25T18:48:38.123456Z",\
    "segments":[{"idx":0,"start_seconds":0,"end_seconds":1.5,"text":"Hola mundo","speaker":null}]}
    """
    let job = try APIJSON.decoder().decode(Job.self, from: Data(json.utf8))
    #expect(job.originalFilename == "reunión.m4a")
    #expect(job.segments[0].endSeconds == 1.5)
    #expect(job.createdAt.timeIntervalSince1970 > 0)
    let wholeDate = json.replacingOccurrences(of: ".123456Z", with: "Z")
    #expect(try APIJSON.decoder().decode(Job.self, from: Data(wholeDate.utf8)).createdAt < job.createdAt)
    let user = try APIJSON.decoder().decode(User.self, from: Data(#"{"id":"1","email":"a@b.c","display_name":"Ana"}"#.utf8))
    #expect(user.displayName == "Ana")
    let model = try APIJSON.decoder().decode(ModelInfo.self, from: Data(#"{"name":"small","ram_gb":2.0,"speed_factor":0.5,"role":"balanced"}"#.utf8))
    #expect(model.ramGb == 2)

    let payload = ImportJobPayload(job: job)
    let encoded = try APIJSON.encoder().encode(payload)
    let dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(dict?["original_filename"] as? String == "reunión.m4a")
    #expect(dict?["duration_seconds"] as? Double == 63.25)
    #expect(dict?["model"] as? String == "small")
    let segments = dict?["segments"] as? [[String: Any]]
    #expect(segments?.first?["start_seconds"] as? Double == 0.0)
    #expect(segments?.first?["end_seconds"] as? Double == 1.5)
}
