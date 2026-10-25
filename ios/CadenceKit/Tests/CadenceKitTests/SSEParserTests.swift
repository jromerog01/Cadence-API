import Testing
@testable import CadenceKit

@Test func parsesSplitSSEFramesAndComments() {
    var parser = SSEParser()
    #expect(parser.feed(": heartbeat\n\nevent: pro").isEmpty)
    #expect(parser.feed("gress\ndata: {\"progress\":0.5}\r\n\r\n") == [
        SSEMessage(event: "progress", data: "{\"progress\":0.5}")
    ])
    #expect(parser.feed("data: first\ndata: second\n\n") == [
        SSEMessage(event: "message", data: "first\nsecond")
    ])
}
