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

    @Test("a session sends the provider saved with its conversation")
    func sessionSendsStoredProvider() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "T", model: "opus", provider: "anthropic")
        let service = FakeChatService(scripts: [.deltas(["Hi"])])
        let session = ChatSession(service: service, model: "default-model", store: store, conversationID: conversation.id)

        await session.send("Hello")

        #expect(session.modelChoice == ModelChoice(model: "opus", provider: "anthropic"))
        #expect(service.recordedModels() == ["opus"])
        #expect(service.recordedProviders() == ["anthropic"])
    }

    @Test("a conversation saved with a model but no provider sends none, whatever the fallback")
    func sessionWithoutProvider() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "T", model: "hermes-agent")
        let service = FakeChatService(scripts: [.deltas(["Hi"])])
        let session = ChatSession(
            service: service, model: "default-model", provider: "ignored", store: store, conversationID: conversation.id)

        await session.send("Hello")

        #expect(service.recordedProviders() == [nil])
    }

    @Test("createConversation(model:provider:) saves both and drops a blank provider")
    func createWithProvider() throws {
        let store = InMemoryConversationStore()
        let browser = ConversationBrowser(store: store, service: FakeChatService(scripts: []), model: "default-model")

        let withProvider = try browser.createConversation(model: "opus", provider: "anthropic")
        let blankProvider = try browser.createConversation(model: "fast", provider: "  ")

        #expect(try store.conversation(id: withProvider)?.provider == "anthropic")
        #expect(browser.summaries.first { $0.id == withProvider }?.provider == "anthropic")
        #expect(try store.conversation(id: blankProvider)?.provider == nil)
    }

    @Test("the display name shows the provider before the model")
    func displayName() {
        #expect(ModelChoice(model: "opus", provider: "anthropic").displayName == "anthropic · opus")
        #expect(ModelChoice(model: "hermes-agent").displayName == "hermes-agent")
    }
}
