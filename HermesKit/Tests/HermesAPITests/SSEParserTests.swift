import Foundation
import Testing

@testable import HermesAPI

@Suite("SSE parser")
struct SSEParserTests {
    private func fixtureBytes(_ name: String, _ ext: String) throws -> [UInt8] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        return [UInt8](try Data(contentsOf: url))
    }

    /// Feeds the parser one byte at a time, to split every line at the worst possible places.
    private func parseByteByByte(_ bytes: [UInt8]) -> [SSEEvent] {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for byte in bytes {
            events += parser.feed(CollectionOfOne(byte))
        }
        events += parser.finish()
        return events
    }

    private func parseWhole(_ bytes: [UInt8]) -> [SSEEvent] {
        var parser = SSEParser()
        return parser.feed(bytes) + parser.finish()
    }

    @Test("a fixture stream yields data in order, stops on [DONE], and ignores comments and other fields")
    func fixtureStream() throws {
        let events = parseWhole(try fixtureBytes("chat_stream", "sse"))

        #expect(events.count == 4)
        let deltas = events.compactMap { event -> String? in
            guard case .data(let payload) = event else { return nil }
            return try? JSONDecoder().decode(ChatChunk.self, from: Data(payload.utf8)).contentDelta
        }
        #expect(deltas == ["Bon", "jour"])
        #expect(events.last == .done)
    }

    @Test("a line split byte by byte is reassembled identically")
    func splitBytesMatchWholeParse() throws {
        let bytes = try fixtureBytes("chat_stream", "sse")
        #expect(parseByteByByte(bytes) == parseWhole(bytes))
    }

    @Test("CRLF line endings are handled")
    func crlf() throws {
        let events = parseWhole(try fixtureBytes("crlf_stream", "sse"))
        #expect(events.count == 2)
        #expect(events.last == .done)
        guard case .data(let payload) = events.first else {
            Issue.record("the first event must be data")
            return
        }
        #expect(payload.hasPrefix(#"{"id":"c2""#))
    }

    @Test("[DONE] ends the stream: following bytes are ignored")
    func doneStopsParsing() {
        var parser = SSEParser()
        let events = parser.feed(Array("data: [DONE]\ndata: {\"after\":1}\n".utf8))
        #expect(events == [.done])
        #expect(parser.hasFinished)
        #expect(parser.feed(Array("data: x\n".utf8)).isEmpty)
    }

    @Test("empty lines and comments are ignored")
    func emptyLinesAndComments() {
        #expect(parseWhole(Array("\n\n: ping\n\n:\n".utf8)).isEmpty)
    }

    @Test("fields other than data (event, id, retry) are ignored")
    func otherFieldsIgnored() {
        #expect(parseWhole(Array("event: message\nid: 7\nretry: 1000\n".utf8)).isEmpty)
    }

    @Test("a last line without a trailing newline is emitted by finish()")
    func lastLineWithoutNewline() {
        var parser = SSEParser()
        #expect(parser.feed(Array(#"data: {"a":1}"#.utf8)).isEmpty)
        #expect(parser.finish() == [.data(#"{"a":1}"#)])
    }

    @Test("invalid JSON stays a plain payload: decoding fails cleanly, without a crash")
    func invalidJSONIsTypedError() {
        let events = parseWhole(Array("data: {not json\n".utf8))
        #expect(events == [.data("{not json")])

        guard case .data(let payload) = events.first else {
            Issue.record("expected a data event")
            return
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ChatChunk.self, from: Data(payload.utf8))
        }
    }

    @Test("sseEvents: the async stream produces the same events as the synchronous parser")
    func asyncStreamMatchesSync() async throws {
        let bytes = try fixtureBytes("chat_stream", "sse")
        let source = AsyncStream<UInt8> { continuation in
            for byte in bytes {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var received: [SSEEvent] = []
        for try await event in sseEvents(source) {
            received.append(event)
        }
        #expect(received == parseWhole(bytes))
    }
}
