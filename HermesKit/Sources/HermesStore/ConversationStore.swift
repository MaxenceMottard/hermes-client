import Foundation

/// A stored message. Its position in a conversation is its index in `StoredConversation.messages`.
public struct StoredMessage: Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// A full conversation, with its messages in order.
public struct StoredConversation: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    /// The model the conversation talks to. `nil` for conversations saved before models were stored.
    public var model: String?
    /// Provider slug of `model` (for example `anthropic`). `nil` when the instance picks the provider.
    public var provider: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [StoredMessage]

    public init(
        id: UUID,
        title: String,
        model: String? = nil,
        provider: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        messages: [StoredMessage]
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.provider = provider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

/// A conversation as shown in a list, without its messages.
public struct ConversationSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    /// The model of the conversation, `nil` when it was saved without one.
    public var model: String?
    /// Provider slug of `model`, `nil` when the instance picks the provider.
    public var provider: String?
    public var updatedAt: Date

    public init(id: UUID, title: String, model: String? = nil, provider: String? = nil, updatedAt: Date) {
        self.id = id
        self.title = title
        self.model = model
        self.provider = provider
        self.updatedAt = updatedAt
    }
}

public enum ConversationStoreError: Error, Equatable {
    case notFound(UUID)
}

/// Persistence of conversations. Implemented in memory (tests) and with SwiftData (app).
/// Main-actor isolated because the app reads and writes it from the UI.
@MainActor
public protocol ConversationStore: AnyObject {
    /// All conversations, most recently updated first.
    func summaries() throws -> [ConversationSummary]
    func conversation(id: UUID) throws -> StoredConversation?
    /// Creates an empty conversation bound to `model` on `provider` (`nil` leaves them unset).
    @discardableResult
    func createConversation(title: String, model: String?, provider: String?) throws -> StoredConversation
    /// Replaces every message of the conversation and bumps its `updatedAt`.
    func replaceMessages(_ messages: [StoredMessage], inConversation id: UUID) throws
    /// Renames the conversation. Does not change its position in the list.
    func rename(conversation id: UUID, to title: String) throws
    func deleteConversation(id: UUID) throws
}

extension ConversationStore {
    /// Creates an empty conversation with no model set.
    @discardableResult
    public func createConversation(title: String) throws -> StoredConversation {
        try createConversation(title: title, model: nil, provider: nil)
    }

    /// Creates an empty conversation bound to `model`, with no provider set.
    @discardableResult
    public func createConversation(title: String, model: String?) throws -> StoredConversation {
        try createConversation(title: title, model: model, provider: nil)
    }
}

/// Non-persistent store. Used by tests and as a fallback.
@MainActor
public final class InMemoryConversationStore: ConversationStore {
    private var conversations: [UUID: StoredConversation] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func summaries() throws -> [ConversationSummary] {
        conversations.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .map {
                ConversationSummary(
                    id: $0.id, title: $0.title, model: $0.model, provider: $0.provider, updatedAt: $0.updatedAt)
            }
    }

    public func conversation(id: UUID) throws -> StoredConversation? {
        conversations[id]
    }

    public func createConversation(title: String, model: String?, provider: String?) throws -> StoredConversation {
        let date = now()
        let conversation = StoredConversation(
            id: UUID(), title: title, model: model, provider: provider, createdAt: date, updatedAt: date, messages: []
        )
        conversations[conversation.id] = conversation
        return conversation
    }

    public func replaceMessages(_ messages: [StoredMessage], inConversation id: UUID) throws {
        guard var conversation = conversations[id] else {
            throw ConversationStoreError.notFound(id)
        }
        conversation.messages = messages
        conversation.updatedAt = now()
        conversations[id] = conversation
    }

    public func rename(conversation id: UUID, to title: String) throws {
        guard var conversation = conversations[id] else {
            throw ConversationStoreError.notFound(id)
        }
        conversation.title = title
        conversations[id] = conversation
    }

    public func deleteConversation(id: UUID) throws {
        guard conversations.removeValue(forKey: id) != nil else {
            throw ConversationStoreError.notFound(id)
        }
    }
}
