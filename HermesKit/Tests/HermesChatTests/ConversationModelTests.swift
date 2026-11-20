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
}
