import Foundation
import Testing
@testable import CadenceKit

@Test func exportsMatchPythonByteForByte() throws {
    let root = Bundle.module.resourceURL!.appending(path: "Fixtures")
    let job = try APIJSON.decoder().decode(Job.self, from: Data(contentsOf: root.appending(path: "job.json")))
    for format in ["txt", "md", "json", "srt", "vtt"] {
        let expected = try Data(contentsOf: root.appending(path: "expected.\(format)"))
        #expect(Data(try TextExporter.render(job, format: format).utf8) == expected, "Formato: \(format)")
    }
}
