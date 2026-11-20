import Foundation
import Testing

@testable import HermesStore

/// Clock shared by a test and its store, so that ordering by `updatedAt` is deterministic.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

@MainActor
@Suite("InMemoryConversationStore")
struct InMemoryConversationStoreTests {
    private func makeStore() -> (InMemoryConversationStore, TestClock) {
        let clock = TestClock()
        return (InMemoryConversationStore(now: { clock.now() }), clock)
    }

    @Test("the model given at creation is kept in the conversation and its summary")
    func createKeepsModel() throws {
        let (store, _) = makeStore()
        let created = try store.createConversation(title: "T", model: "some-model")

        #expect(try store.conversation(id: created.id)?.model == "some-model")
        #expect(try store.summaries().first?.model == "some-model")
    }

    @Test("the provider given at creation is kept in the conversation and its summary")
    func createKeepsProvider() throws {
        let (store, _) = makeStore()
        let created = try store.createConversation(title: "T", model: "opus", provider: "anthropic")

        #expect(try store.conversation(id: created.id)?.provider == "anthropic")
        #expect(try store.summaries().first?.provider == "anthropic")
    }

    @Test("a conversation created without a model has none")
    func createWithoutModel() throws {
        let (store, _) = makeStore()
        let created = try store.createConversation(title: "T")

        #expect(created.model == nil)
        #expect(try store.summaries().first?.model == nil)
    }

    @Test("a created conversation is empty and found by id")
    func createAndFetch() throws {
        let (store, _) = makeStore()
        let created = try store.createConversation(title: "New conversation")

        #expect(created.messages.isEmpty)
        #expect(try store.conversation(id: created.id) == created)
    }

    @Test("replaceMessages stores the messages in order and bumps updatedAt")
    func replaceMessages() throws {
        let (store, clock) = makeStore()
        let created = try store.createConversation(title: "T")
        clock.advance(by: 60)

        let messages = [StoredMessage(role: "user", content: "Hi"), StoredMessage(role: "assistant", content: "Hello")]
        try store.replaceMessages(messages, inConversation: created.id)

        let fetched = try #require(try store.conversation(id: created.id))
        #expect(fetched.messages == messages)
        #expect(fetched.updatedAt > created.updatedAt)
    }

    @Test("summaries are sorted by most recent activity")
    func summariesOrder() throws {
        let (store, clock) = makeStore()
        let older = try store.createConversation(title: "older")
        clock.advance(by: 10)
        let newer = try store.createConversation(title: "newer")
        clock.advance(by: 10)
        try store.replaceMessages([StoredMessage(role: "user", content: "x")], inConversation: older.id)

        let ids = try store.summaries().map(\.id)
        #expect(ids == [older.id, newer.id])
    }

    @Test("rename changes the title without changing the position in the list")
    func renameKeepsPosition() throws {
        let (store, clock) = makeStore()
        let first = try store.createConversation(title: "first")
        clock.advance(by: 10)
        _ = try store.createConversation(title: "second")

        try store.rename(conversation: first.id, to: "Renamed")

        let summaries = try store.summaries()
        #expect(summaries.last?.id == first.id)
        #expect(summaries.last?.title == "Renamed")
    }

    @Test("delete removes the conversation; deleting twice throws notFound")
    func delete() throws {
        let (store, _) = makeStore()
        let created = try store.createConversation(title: "T")

        try store.deleteConversation(id: created.id)

        #expect(try store.conversation(id: created.id) == nil)
        #expect(throws: ConversationStoreError.notFound(created.id)) {
            try store.deleteConversation(id: created.id)
        }
    }

    @Test("operations on an unknown id throw notFound")
    func unknownIdThrows() {
        let (store, _) = makeStore()
        let unknown = UUID()
        #expect(throws: ConversationStoreError.notFound(unknown)) {
            try store.replaceMessages([], inConversation: unknown)
        }
        #expect(throws: ConversationStoreError.notFound(unknown)) {
            try store.rename(conversation: unknown, to: "x")
        }
    }
}
