import Foundation
import HermesStore
import Testing

@testable import HermesChat

@MainActor
@Suite("Conversation model")
struct ConversationModelTests {
    @Test("a session sends to the model saved with its conversation")
    func sessionUsesStoredModel() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "T", model: "stored-model")
        let service = FakeChatService(scripts: [.deltas(["Hi"])])
        let session = ChatSession(service: service, model: "default-model", store: store, conversationID: conversation.id)

        await session.send("Hello")

        #expect(session.model == "stored-model")
        #expect(service.recordedModels() == ["stored-model"])
    }

    @Test("a conversation saved without a model falls back to the default model")
    func sessionFallsBackToDefault() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "T")
        let service = FakeChatService(scripts: [.deltas(["Hi"])])
        let session = ChatSession(service: service, model: "default-model", store: store, conversationID: conversation.id)

        await session.send("Hello")

        #expect(session.model == "default-model")
        #expect(service.recordedModels() == ["default-model"])
    }

    @Test("the first conversation is created with the default model")
    func firstConversationUsesDefault() throws {
        let store = InMemoryConversationStore()
        let browser = ConversationBrowser(store: store, service: FakeChatService(scripts: []), model: "default-model")

        #expect(browser.summaries.first?.model == "default-model")
        #expect(browser.session?.model == "default-model")
    }

    @Test("createConversation(model:) saves the chosen model and opens a session on it")
    func createWithModel() throws {
        let store = InMemoryConversationStore()
        let browser = ConversationBrowser(store: store, service: FakeChatService(scripts: []), model: "default-model")

        let id = try browser.createConversation(model: "  other-model ")

        #expect(try store.conversation(id: id)?.model == "other-model")
        #expect(browser.summaries.first { $0.id == id }?.model == "other-model")
        #expect(browser.session?.model == "other-model")
    }

    @Test("a blank model falls back to the default model")
    func createWithBlankModel() throws {
        let store = InMemoryConversationStore()
        let browser = ConversationBrowser(store: store, service: FakeChatService(scripts: []), model: "default-model")

        let id = try browser.createConversation(model: "   ")

        #expect(try store.conversation(id: id)?.model == "default-model")
    }

    @Test("reopening a conversation keeps its own model")
    func reopenKeepsModel() throws {
        let store = InMemoryConversationStore()
        let browser = ConversationBrowser(store: store, service: FakeChatService(scripts: []), model: "default-model")
        let first = try #require(browser.selectedID)
        _ = try browser.createConversation(model: "other-model")

        browser.select(first)

        #expect(browser.session?.model == "default-model")
    }
}
