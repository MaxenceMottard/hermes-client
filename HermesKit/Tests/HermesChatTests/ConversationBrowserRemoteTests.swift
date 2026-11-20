import Foundation
import HermesAPI
import HermesStore
import Testing

@testable import HermesChat

@MainActor
@Suite("ConversationBrowser remote sessions")
struct ConversationBrowserRemoteTests {
    private func makeBrowser(withRemote: Bool) -> ConversationBrowser {
        ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: []),
            model: "m",
            remoteSessions: withRemote ? RemoteSessionList(source: FakeSessionSource(pages: [])) : nil
        )
    }

    @Test("opening a remote session shows it in place of the local conversation")
    func openRemoteReplacesLocal() {
        let browser = makeBrowser(withRemote: true)
        #expect(browser.session != nil)

        browser.openRemote(RemoteSession(id: "remote-1", title: "Notes"))

        #expect(browser.openedRemote?.sessionID == "remote-1")
        #expect(browser.openedRemote?.title == "Notes")
        #expect(browser.session == nil)
        #expect(browser.selectedID == nil)
    }

    @Test("selecting a local conversation closes the remote session")
    func selectLocalClosesRemote() throws {
        let browser = makeBrowser(withRemote: true)
        let local = try #require(browser.summaries.first?.id)
        browser.openRemote(RemoteSession(id: "remote-1"))

        browser.select(local)

        #expect(browser.openedRemote == nil)
        #expect(browser.selectedID == local)
        #expect(browser.session != nil)
    }

    @Test("creating a conversation closes the remote session")
    func createClosesRemote() throws {
        let browser = makeBrowser(withRemote: true)
        browser.openRemote(RemoteSession(id: "remote-1"))

        _ = try browser.createConversation()

        #expect(browser.openedRemote == nil)
        #expect(browser.session != nil)
    }

    @Test("without a configured instance, opening a remote session does nothing")
    func openRemoteWithoutInstance() {
        let browser = makeBrowser(withRemote: false)
        let local = browser.selectedID

        browser.openRemote(RemoteSession(id: "remote-1"))

        #expect(browser.openedRemote == nil)
        #expect(browser.selectedID == local)
    }

    @Test("opening a remote session starts loading its messages without the view")
    func openRemoteStartsLoading() async throws {
        let source = GatedMessageSource(page: SessionMessagesPage(
            sessionID: "remote-1",
            messages: [SessionMessage(id: "1", role: "user", content: "Hi")],
            hasMore: false
        ))
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: []),
            model: "m",
            remoteSessions: RemoteSessionList(source: source)
        )

        browser.openRemote(RemoteSession(id: "remote-1"))
        await waitForPendingRequest(source)
        await source.release()
        let transcript = try #require(browser.openedRemote)
        // Waits for the request the browser started; calling `load()` here could send a second one.
        await waitUntilLoadEnds(transcript)

        #expect(await source.requestCount == 1)
        #expect(transcript.state == .loaded)
        #expect(transcript.lines.map(\.text) == ["Hi"])
    }

    @Test("after a fork the selection follows the fork and selecting it keeps the transcript")
    func selectionFollowsFork() async throws {
        let fork = RemoteSession(id: "api_fork", source: "api_server")
        let source = FakeChatStreamSource(events: [.completed("Hello")], forkResult: .success(fork))
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: []),
            model: "m",
            remoteSessions: RemoteSessionList(source: source)
        )
        browser.openRemote(RemoteSession(id: "local-1", source: "local"))
        let transcript = try #require(browser.openedRemote)

        await transcript.send("Hi")
        browser.selectEntry(SidebarEntry.remoteID("api_fork"))

        #expect(browser.selectedEntryID == SidebarEntry.remoteID("api_fork"))
        #expect(browser.openedRemote === transcript)
        #expect(browser.remoteSessions?.sessions.map(\.id) == ["api_fork"])
    }
}

