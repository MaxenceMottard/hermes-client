import Foundation
import HermesAPI
import Testing

@testable import HermesChat

/// Returns scripted pages and records the offsets it was asked for.
actor FakeSessionSource: SessionListing {
    private var pages: [Result<SessionPage, HermesAPIError>]
    private(set) var offsets: [Int] = []

    init(pages: [Result<SessionPage, HermesAPIError>]) {
        self.pages = pages
    }

    func listSessions(limit: Int, offset: Int) async throws -> SessionPage {
        offsets.append(offset)
        guard !pages.isEmpty else { return SessionPage(sessions: [], hasMore: false) }
        return try pages.removeFirst().get()
    }

    func listSessionMessages(sessionID: String, limit: Int, offset: Int) async throws -> SessionMessagesPage {
        throw HermesAPIError.notFound
    }

    func streamSessionChat(sessionID: String, message: String) -> AsyncThrowingStream<SessionChatEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func forkSession(sessionID: String) async throws -> RemoteSession {
        throw HermesAPIError.notFound
    }
}

@MainActor
@Suite("RemoteSessionList")
struct RemoteSessionListTests {
    private func session(_ id: String, pinned: Bool = false) -> RemoteSession {
        RemoteSession(id: id, title: id, pinned: pinned)
    }

    @Test("reload loads the first page at offset 0 and records hasMore")
    func reloadLoadsFirstPage() async {
        let source = FakeSessionSource(pages: [
            .success(SessionPage(sessions: [session("a"), session("b")], hasMore: true)),
        ])
        let list = RemoteSessionList(source: source)

        await list.reload()

        #expect(list.sessions.map(\.id) == ["a", "b"])
        #expect(list.hasMore)
        #expect(list.state == .loaded)
        #expect(await source.offsets == [0])
    }

    @Test("loadNextPage appends the next page at the offset of the rows received")
    func loadNextPageAppends() async {
        let source = FakeSessionSource(pages: [
            .success(SessionPage(sessions: [session("a"), session("b")], hasMore: true)),
            .success(SessionPage(sessions: [session("c")], hasMore: false)),
        ])
        let list = RemoteSessionList(source: source)

        await list.reload()
        await list.loadNextPage()

        #expect(list.sessions.map(\.id) == ["a", "b", "c"])
        #expect(!list.hasMore)
        #expect(await source.offsets == [0, 2])
    }

    @Test("pinned sessions do not move the offset, because the instance back-fills them past the limit")
    func pinnedDoNotShiftOffset() async {
        let source = FakeSessionSource(pages: [
            .success(SessionPage(sessions: [session("pin", pinned: true), session("a"), session("b")], hasMore: true)),
            .success(SessionPage(sessions: [session("c")], hasMore: false)),
        ])
        let list = RemoteSessionList(source: source)

        await list.reload()
        await list.loadNextPage()

        #expect(await source.offsets == [0, 2])
    }

    @Test("a session returned by two pages is listed once")
    func deduplicatesAcrossPages() async {
        let source = FakeSessionSource(pages: [
            .success(SessionPage(sessions: [session("pin", pinned: true), session("a")], hasMore: true)),
            .success(SessionPage(sessions: [session("pin", pinned: true), session("b")], hasMore: false)),
        ])
        let list = RemoteSessionList(source: source)

        await list.reload()
        await list.loadNextPage()

        #expect(list.sessions.map(\.id) == ["pin", "a", "b"])
    }

    @Test("loadNextPage does nothing when the instance reported no more pages")
    func noRequestWithoutMore() async {
        let source = FakeSessionSource(pages: [
            .success(SessionPage(sessions: [session("a")], hasMore: false)),
        ])
        let list = RemoteSessionList(source: source)

        await list.reload()
        await list.loadNextPage()

        #expect(await source.offsets == [0])
    }

    @Test("a failed reload keeps the state as failed with the error")
    func reloadFailure() async {
        let source = FakeSessionSource(pages: [.failure(.unauthorized)])
        let list = RemoteSessionList(source: source)

        await list.reload()

        #expect(list.state == .failed(.unauthorized))
        #expect(list.sessions.isEmpty)
    }

    @Test("a failed next page keeps the sessions already loaded")
    func nextPageFailureKeepsList() async {
        let source = FakeSessionSource(pages: [
            .success(SessionPage(sessions: [session("a")], hasMore: true)),
            .failure(.network),
        ])
        let list = RemoteSessionList(source: source)

        await list.reload()
        await list.loadNextPage()

        #expect(list.state == .failed(.network))
        #expect(list.sessions.map(\.id) == ["a"])
        #expect(list.hasMore)
    }

    @Test("a transcript accepts messages only for a session the API may write to")
    func transcriptAcceptsMessages() {
        let list = RemoteSessionList(source: FakeSessionSource(pages: []))

        #expect(list.transcript(for: RemoteSession(id: "a", source: "api_server")).acceptsMessages)
        #expect(!list.transcript(for: RemoteSession(id: "b", source: "local")).acceptsMessages)
    }

    @Test("a fork takes the row of the original session")
    func forkReplacesRow() async {
        let source = FakeSessionSource(pages: [
            .success(SessionPage(sessions: [session("a"), session("local-1"), session("c")], hasMore: false)),
        ])
        let list = RemoteSessionList(source: source)
        await list.reload()
        let transcript = list.transcript(for: RemoteSession(id: "local-1", source: "local"))

        transcript.onFork?(RemoteSession(id: "api_fork", source: "api_server"))

        #expect(list.sessions.map(\.id) == ["a", "api_fork", "c"])
    }

    @Test("a fork whose original is no longer listed goes to the top, once")
    func forkInsertedAtTop() {
        let list = RemoteSessionList(source: FakeSessionSource(pages: []))
        list.replace("gone", with: session("api_fork"))
        list.replace("gone", with: session("api_fork"))

        #expect(list.sessions.map(\.id) == ["api_fork"])
    }
}
