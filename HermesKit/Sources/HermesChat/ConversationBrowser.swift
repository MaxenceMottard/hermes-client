import Foundation
import HermesStore

#if !os(Linux)
    import Observation
#endif

/// Title given to a new conversation until its first message renames it.
public enum ConversationTitle {
    public static let placeholder = "New conversation"
}

/// The list of conversations and the one currently open. Keeps exactly one conversation open.
///
/// `@Observable` is applied on Apple platforms, see `ChatSession` for why it is left out on Linux.
@MainActor
#if !os(Linux)
    @Observable
#endif
public final class ConversationBrowser {
    public private(set) var summaries: [ConversationSummary] = []
    public private(set) var selectedID: UUID?
    public private(set) var session: ChatSession?

    private let store: any ConversationStore
    private let service: any ChatService
    private let model: String

    /// Loads the conversations and opens the most recent one. Creates a conversation if there is none.
    public init(store: any ConversationStore, service: any ChatService, model: String) {
        self.store = store
        self.service = service
        self.model = model
        refresh()
        if summaries.isEmpty {
            _ = try? createConversation()
        } else {
            select(summaries[0].id)
        }
    }

    /// Reloads the list from the store. Keeps the current list if the store fails.
    public func refresh() {
        if let loaded = try? store.summaries() {
            summaries = loaded
        }
    }

    /// Creates a conversation and opens it.
    @discardableResult
    public func createConversation() throws -> UUID {
        let conversation = try store.createConversation(title: ConversationTitle.placeholder)
        refresh()
        select(conversation.id)
        return conversation.id
    }

    /// Opens a conversation. Selecting the open one again keeps its session, including a reply in progress.
    public func select(_ id: UUID?) {
        guard id != selectedID else { return }
        guard let id, (try? store.conversation(id: id)) != nil else {
            selectedID = nil
            session = nil
            return
        }
        selectedID = id
        session = ChatSession(service: service, model: model, store: store, conversationID: id)
    }

    /// Deletes a conversation. If it was open, the most recent remaining one opens; a new one is created if none is left.
    public func delete(_ id: UUID) throws {
        let wasSelected = id == selectedID
        if wasSelected {
            session?.stop()
        }
        try store.deleteConversation(id: id)
        refresh()
        if wasSelected {
            selectedID = nil
            session = nil
            select(summaries.first?.id)
        }
        if summaries.isEmpty {
            try createConversation()
        }
    }

    /// Renames a conversation. Blank titles are ignored.
    public func rename(_ id: UUID, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try store.rename(conversation: id, to: trimmed)
        refresh()
    }
}
