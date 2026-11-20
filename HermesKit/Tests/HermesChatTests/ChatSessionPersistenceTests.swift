import Foundation
import HermesAPI
import HermesStore
import Testing

@testable import HermesChat

@MainActor
@Suite("ChatSession persistence")
struct ChatSessionPersistenceTests {
    @Test("a send saves the user message and the reply to the conversation")
    func sendIsSaved() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "T")
        let session = ChatSession(
            service: FakeChatService(scripts: [.deltas(["Hello"])]),
            model: "m",
            store: store,
            conversationID: conversation.id
        )

        await session.send("Hi")

        let saved = try #require(try store.conversation(id: conversation.id))
        #expect(
            saved.messages == [
                StoredMessage(role: "user", content: "Hi"),
                StoredMessage(role: "assistant", content: "Hello"),
            ])
    }

    @Test("a new session on the same conversation restores the history and sends it")
    func reopenRestoresHistory() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "T")
        let first = ChatSession(
            service: FakeChatService(scripts: [.deltas(["A1"])]),
            model: "m",
            store: store,
            conversationID: conversation.id
        )
        await first.send("Q1")

        let fake = FakeChatService(scripts: [.deltas(["A2"])])
        let reopened = ChatSession(service: fake, model: "m", store: store, conversationID: conversation.id)
        #expect(reopened.messages.count == 2)

        await reopened.send("Q2")

        #expect(
            fake.recordedRequests().first == [
                ChatMessage(role: "user", content: "Q1"),
                ChatMessage(role: "assistant", content: "A1"),
                ChatMessage(role: "user", content: "Q2"),
            ])
    }

    @Test("a failed reply saves only the user message, not an empty placeholder")
    func failureSavesUserOnly() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "T")
        let session = ChatSession(
            service: FakeChatService(scripts: [.fail(URLError(.notConnectedToInternet))]),
            model: "m",
            store: store,
            conversationID: conversation.id
        )

        await session.send("Hi")

        let saved = try #require(try store.conversation(id: conversation.id))
        #expect(saved.messages == [StoredMessage(role: "user", content: "Hi")])
    }

    @Test("the first message gives the conversation a title, and later messages do not change it")
    func firstMessageTitlesConversation() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: ConversationTitle.placeholder)
        let session = ChatSession(
            service: FakeChatService(scripts: [.deltas(["A"]), .deltas(["B"])]),
            model: "m",
            store: store,
            conversationID: conversation.id
        )

        await session.send("Plan a trip to Lisbon")
        #expect(try store.conversation(id: conversation.id)?.title == "Plan a trip to Lisbon")

        await session.send("And hotels?")
        #expect(try store.conversation(id: conversation.id)?.title == "Plan a trip to Lisbon")
    }

    @Test("a title chosen by the user is kept after the first message")
    func userTitleIsKept() async throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "Work")
        let session = ChatSession(
            service: FakeChatService(scripts: [.deltas(["A"])]),
            model: "m",
            store: store,
            conversationID: conversation.id
        )

        await session.send("Quarterly report")

        #expect(try store.conversation(id: conversation.id)?.title == "Work")
    }
}
