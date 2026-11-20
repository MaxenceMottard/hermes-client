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
}
