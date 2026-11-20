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
}
