import Foundation
import HermesStore
import Testing

@testable import HermesChat

@MainActor
@Suite("ConversationBrowser")
struct ConversationBrowserTests {
    private func makeBrowser(
        store: InMemoryConversationStore = InMemoryConversationStore()
    ) -> ConversationBrowser {
        ConversationBrowser(store: store, service: FakeChatService(scripts: []), model: "m")
    }

    @Test("with no conversation, one is created and opened")
    func createsFirstConversation() {
        let browser = makeBrowser()

        #expect(browser.summaries.count == 1)
        #expect(browser.selectedID == browser.summaries.first?.id)
        #expect(browser.session != nil)
        #expect(browser.summaries.first?.title == ConversationTitle.placeholder)
    }

    @Test("an existing conversation is opened on start, most recent first")
    func opensMostRecent() throws {
        let store = InMemoryConversationStore()
        _ = try store.createConversation(title: "old")
        let recent = try store.createConversation(title: "recent")

        let browser = makeBrowser(store: store)

        #expect(browser.selectedID == recent.id)
    }

    @Test("createConversation adds a conversation and opens it")
    func createOpens() throws {
        let browser = makeBrowser()
        let before = browser.selectedID

        let created = try browser.createConversation()

        #expect(browser.summaries.count == 2)
        #expect(browser.selectedID == created)
        #expect(created != before)
    }

    @Test("selecting the open conversation keeps its session")
    func selectSameKeepsSession() throws {
        let browser = makeBrowser()
        let session = browser.session
        let id = try #require(browser.selectedID)

        browser.select(id)

        #expect(browser.session === session)
    }

    @Test("deleting the open conversation opens the next most recent one")
    func deleteSelectedOpensNext() throws {
        let browser = makeBrowser()
        _ = try browser.createConversation()
        let current = try #require(browser.selectedID)
        let other = try #require(browser.summaries.first { $0.id != current }?.id)

        try browser.delete(current)

        #expect(browser.summaries.map(\.id) == [other])
        #expect(browser.selectedID == other)
    }

    @Test("deleting the last conversation creates a new one")
    func deleteLastCreatesNew() throws {
        let browser = makeBrowser()
        let only = try #require(browser.selectedID)

        try browser.delete(only)

        #expect(browser.summaries.count == 1)
        #expect(browser.selectedID != only)
        #expect(browser.session != nil)
    }

    @Test("rename trims the title and ignores blank titles")
    func rename() throws {
        let browser = makeBrowser()
        let id = try #require(browser.selectedID)

        try browser.rename(id, to: "  Trip planning  ")
        #expect(browser.summaries.first?.title == "Trip planning")

        try browser.rename(id, to: "   ")
        #expect(browser.summaries.first?.title == "Trip planning")
    }

    @Test("a title is derived from the first line, trimmed and cut to the limit")
    func deriveTitle() {
        #expect(ConversationTitle.derive(from: "  Hello there\nsecond line") == "Hello there")
        #expect(ConversationTitle.derive(from: "   \n  ") == ConversationTitle.placeholder)
        #expect(ConversationTitle.derive(from: "Short") == "Short")
        let long = String(repeating: "a", count: 60)
        let derived = ConversationTitle.derive(from: long, limit: 10)
        #expect(derived == String(repeating: "a", count: 10) + "…")
    }
}
