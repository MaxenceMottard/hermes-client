import Foundation
import HermesAPI
import HermesStore
import Testing

@testable import HermesChat

/// The sidebar selection drives navigation for local and remote rows alike.
@MainActor
@Suite("ConversationBrowser sidebar selection")
struct ConversationBrowserSelectionTests {
    private func makeBrowser(remote: [RemoteSession]) async -> ConversationBrowser {
        let list = RemoteSessionList(source: FakeSessionSource(pages: [
            .success(SessionPage(sessions: remote, hasMore: false)),
        ]))
        await list.reload()
        return ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: []),
            model: "m",
            remoteSessions: list
        )
    }

    @Test("selecting a remote row id opens that session and becomes the selection")
    func selectRemoteEntry() async {
        let browser = await makeBrowser(remote: [RemoteSession(id: "r1", title: "Notes")])

        browser.selectEntry(SidebarEntry.remoteID("r1"))

        #expect(browser.openedRemote?.sessionID == "r1")
        #expect(browser.session == nil)
        #expect(browser.selectedEntryID == "remote-r1")
    }

    @Test("selecting a local row id opens the conversation and closes the remote session")
    func selectLocalEntry() async throws {
        let browser = await makeBrowser(remote: [RemoteSession(id: "r1")])
        let local = try #require(browser.summaries.first?.id)
        browser.selectEntry(SidebarEntry.remoteID("r1"))

        browser.selectEntry(SidebarEntry.localID(local))

        #expect(browser.openedRemote == nil)
        #expect(browser.selectedID == local)
        #expect(browser.selectedEntryID == SidebarEntry.localID(local))
    }

    @Test("a nil selection, as when going back to the list, closes both")
    func deselect() async {
        let browser = await makeBrowser(remote: [RemoteSession(id: "r1")])
        browser.selectEntry(SidebarEntry.remoteID("r1"))

        browser.selectEntry(nil)

        #expect(browser.openedRemote == nil)
        #expect(browser.session == nil)
        #expect(browser.selectedEntryID == nil)
    }

    @Test("selecting the open remote session again keeps its transcript")
    func reselectKeepsTranscript() async {
        let browser = await makeBrowser(remote: [RemoteSession(id: "r1")])
        browser.selectEntry(SidebarEntry.remoteID("r1"))
        let first = browser.openedRemote

        browser.selectEntry(SidebarEntry.remoteID("r1"))

        #expect(browser.openedRemote === first)
    }

    @Test("an unknown row id changes nothing")
    func unknownEntry() async {
        let browser = await makeBrowser(remote: [])
        let before = browser.selectedEntryID

        browser.selectEntry(SidebarEntry.remoteID("missing"))
        browser.selectEntry("garbage")

        #expect(browser.selectedEntryID == before)
        #expect(browser.openedRemote == nil)
    }

    @Test("row ids round-trip to their local and remote ids")
    func entryIDsRoundTrip() {
        let uuid = UUID()

        #expect(SidebarEntry.localUUID(from: SidebarEntry.localID(uuid)) == uuid)
        #expect(SidebarEntry.remoteSessionID(from: SidebarEntry.remoteID("20261120_x")) == "20261120_x")
        #expect(SidebarEntry.localUUID(from: SidebarEntry.remoteID("x")) == nil)
        #expect(SidebarEntry.remoteSessionID(from: "remote-") == nil)
    }
}
