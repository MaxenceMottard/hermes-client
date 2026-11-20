import Foundation
import HermesAPI
import Testing

@testable import HermesChat

/// Streams a scripted reply, optionally failing, and records the messages it was sent.
actor FakeChatStreamSource: SessionListing {
    private let events: [SessionChatEvent]
    private let failure: HermesAPIError?
    private(set) var sent: [String] = []

    init(events: [SessionChatEvent], failure: HermesAPIError? = nil) {
        self.events = events
        self.failure = failure
    }

    func listSessions(limit: Int, offset: Int) async throws -> SessionPage {
        SessionPage(sessions: [], hasMore: false)
    }

    func listSessionMessages(sessionID: String, limit: Int, offset: Int) async throws -> SessionMessagesPage {
        SessionMessagesPage(sessionID: sessionID, messages: [], hasMore: false)
    }

    func streamSessionChat(sessionID: String, message: String) -> AsyncThrowingStream<SessionChatEvent, any Error> {
        sent.append(message)
        let events = events
        let failure = failure
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let failure {
                continuation.finish(throwing: failure)
            } else {
                continuation.finish()
            }
        }
    }
}

@MainActor
@Suite("RemoteTranscript.send")
struct RemoteTranscriptSendTests {
    @Test("the user line appears, then the reply grows with each delta")
    func streamsReply() async {
        let source = FakeChatStreamSource(events: [
            .delta("Hel"), .delta("lo"), .completed("Hello"), .finished,
        ])
        let transcript = RemoteTranscript(sessionID: "s1", title: nil, source: source)

        await transcript.send("  Hi  ")

        #expect(transcript.lines.map(\.role) == ["user", "assistant"])
        #expect(transcript.lines.map(\.text) == ["Hi", "Hello"])
        #expect(!transcript.isSending)
        #expect(transcript.sendError == nil)
        #expect(await source.sent == ["Hi"])
    }

    @Test("a completed event without deltas sets the reply")
    func completedOnly() async {
        let source = FakeChatStreamSource(events: [.completed("Whole reply")])
        let transcript = RemoteTranscript(sessionID: "s1", title: nil, source: source)

        await transcript.send("Hi")

        #expect(transcript.lines.last?.text == "Whole reply")
    }

    @Test("blank text is not sent")
    func blankIgnored() async {
        let source = FakeChatStreamSource(events: [.completed("x")])
        let transcript = RemoteTranscript(sessionID: "s1", title: nil, source: source)

        await transcript.send("   \n ")

        #expect(transcript.lines.isEmpty)
        #expect(await source.sent.isEmpty)
    }

    @Test("a run failure is reported and an empty reply is removed")
    func runFailure() async {
        let source = FakeChatStreamSource(events: [.failed("The model is unavailable.")])
        let transcript = RemoteTranscript(sessionID: "s1", title: nil, source: source)

        await transcript.send("Hi")

        #expect(transcript.sendError == "The model is unavailable.")
        #expect(transcript.lines.map(\.role) == ["user"])
    }

    @Test("a transport failure keeps the partial reply and reports the error")
    func transportFailure() async {
        let source = FakeChatStreamSource(events: [.delta("Par")], failure: .timeout)
        let transcript = RemoteTranscript(sessionID: "s1", title: nil, source: source)

        await transcript.send("Hi")

        #expect(transcript.lines.last?.text == "Par")
        #expect(transcript.sendError == HermesAPIError.timeout.errorDescription)
        #expect(!transcript.isSending)
    }
}
