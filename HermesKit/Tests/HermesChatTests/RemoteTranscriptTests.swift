import Foundation
import HermesAPI
import Testing

@testable import HermesChat

/// Returns scripted message pages and records the (offset, limit) it was asked for.
actor FakeMessageSource: SessionListing {
    private var pages: [Result<SessionMessagesPage, HermesAPIError>]
    private(set) var requests: [(offset: Int, limit: Int)] = []

    init(pages: [Result<SessionMessagesPage, HermesAPIError>]) {
        self.pages = pages
    }

    func listSessions(limit: Int, offset: Int) async throws -> SessionPage {
        SessionPage(sessions: [], hasMore: false)
    }

    func listSessionMessages(sessionID: String, limit: Int, offset: Int) async throws -> SessionMessagesPage {
        requests.append((offset: offset, limit: limit))
        guard !pages.isEmpty else { return SessionMessagesPage(sessionID: sessionID, messages: [], hasMore: false) }
        return try pages.removeFirst().get()
    }
}

@MainActor
@Suite("RemoteTranscript")
struct RemoteTranscriptTests {
    private func message(
        _ id: String, _ role: String, _ content: String?, kind: String? = nil, at seconds: Double? = nil
    ) -> SessionMessage {
        SessionMessage(
            id: id,
            role: role,
            content: content,
            timestamp: seconds.map { Date(timeIntervalSince1970: $0) },
            displayKind: kind
        )
    }

    @Test("only user and assistant messages with text are kept, trimmed, in order")
    func filtersLines() {
        let lines = RemoteTranscript.lines(from: [
            message("1", "user", "  Hello  "),
            message("2", "tool", "{\"result\": 1}"),
            message("3", "system", "You are a helpful agent."),
            message("4", "assistant", "Hi!", at: 100),
            message("5", "assistant", nil),
            message("6", "assistant", "   "),
            message("7", "assistant", "Compaction summary", kind: "hidden"),
        ])

        #expect(lines.map(\.id) == ["1", "4"])
        #expect(lines.map(\.text) == ["Hello", "Hi!"])
        #expect(lines[1].date == Date(timeIntervalSince1970: 100))
        #expect(lines.map(\.role) == ["user", "assistant"])
    }

    @Test("load asks for the first page, oldest first, and keeps hasMore")
    func loadFirstPage() async {
        let source = FakeMessageSource(pages: [
            .success(SessionMessagesPage(
                sessionID: "s1",
                messages: [message("1", "user", "Hi")],
                hasMore: true
            )),
        ])
        let transcript = RemoteTranscript(sessionID: "s1", title: nil, source: source)

        await transcript.load()

        #expect(transcript.lines.map(\.text) == ["Hi"])
        #expect(transcript.hasMore)
        #expect(transcript.state == .loaded)
        #expect(await source.requests.map(\.offset) == [0])
        #expect(await source.requests.map(\.limit) == [RemoteTranscript.pageSize])
    }

    @Test("the next offset counts every received message, including the ones not displayed")
    func loadMoreOffsetCountsHiddenRows() async {
        let source = FakeMessageSource(pages: [
            .success(SessionMessagesPage(
                sessionID: "s1",
                messages: [message("1", "tool", "x"), message("2", "user", "Hi")],
                hasMore: true
            )),
            .success(SessionMessagesPage(
                sessionID: "s1",
                messages: [message("3", "assistant", "Hello")],
                hasMore: false
            )),
        ])
        let transcript = RemoteTranscript(sessionID: "s1", title: nil, source: source)

        await transcript.load()
        await transcript.loadMore()

        #expect(await source.requests.map(\.offset) == [0, 2])
        #expect(transcript.lines.map(\.id) == ["2", "3"])
        #expect(!transcript.hasMore)
    }

    @Test("a failed load keeps the failure with its reason")
    func loadFailure() async {
        let source = FakeMessageSource(pages: [.failure(.notFound)])
        let transcript = RemoteTranscript(sessionID: "gone", title: nil, source: source)

        await transcript.load()

        #expect(transcript.state == .failed(.notFound))
        #expect(transcript.lines.isEmpty)
    }
}
