import Foundation
import HermesAPI
import HermesStore

#if !os(Linux)
    import Observation
#endif

/// Title given to a new conversation until its first message renames it.
public enum ConversationTitle {
    public static let placeholder = "New conversation"

    /// A title taken from the first message: its first line, trimmed, and cut to `limit` characters.
    public static func derive(from text: String, limit: Int = 40) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return placeholder }
        guard trimmed.count > limit else { return trimmed }
        let cut = trimmed.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + "…"
    }
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
    /// The remote session shown in the detail pane, or `nil` when a local conversation is open.
    public private(set) var openedRemote: RemoteTranscript?
    /// Sessions stored on the Hermes instance, or `nil` when no instance is configured.
    public let remoteSessions: RemoteSessionList?

    private let store: any ConversationStore
    private let service: any ChatService
    /// Model given to new conversations when none is chosen or remembered, and used by conversations saved
    /// without a model. `hermes-agent` (the default) lets the instance pick.
    private let model: String
    private let lastModel: (any LastModelStorage)?
    /// Local conversations left while a reply was streaming, by conversation id. The reply keeps running in
    /// its session, so opening the conversation again shows that session instead of a copy read from the
    /// store, which would miss everything received after it was read.
    private var liveSessions: [UUID: ChatSession] = [:]
    /// Remote sessions left while a reply was streaming, for the same reason. The reply exists only in the
    /// transcript that sent the message: the instance offers no way to attach to a turn already running.
    private var liveTranscripts: [RemoteTranscript] = []

    /// Loads the conversations and opens the most recent one. Creates a conversation if there is none.
    /// With a `lastModel` storage, new conversations start on the model chosen last time.
    public init(
        store: any ConversationStore,
        service: any ChatService,
        model: String = ModelChoice.instanceDefault.model,
        remoteSessions: RemoteSessionList? = nil,
        lastModel: (any LastModelStorage)? = nil
    ) {
        self.store = store
        self.service = service
        self.model = model
        self.remoteSessions = remoteSessions
        self.lastModel = lastModel
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

    /// The default model, with no provider: `hermes-agent` unless the browser was built with another one.
    public var defaultChoice: ModelChoice {
        ModelChoice(model: model)
    }

    /// The model a new conversation starts on: the last one chosen, else the default model.
    public var preferredChoice: ModelChoice {
        lastModel?.load() ?? defaultChoice
    }

    /// Creates a conversation bound to `model` on `provider` and opens it. A chosen model is remembered as
    /// the last used one. A `nil` or blank model falls back to `preferredChoice` and is not remembered.
    @discardableResult
    public func createConversation(model chosen: String? = nil, provider: String? = nil) throws -> UUID {
        let explicit = chosen.flatMap { ModelChoice(model: $0, provider: provider).normalized }
        let choice = explicit ?? preferredChoice
        let conversation = try store.createConversation(
            title: ConversationTitle.placeholder,
            model: choice.model,
            provider: choice.provider
        )
        if let explicit {
            lastModel?.save(explicit)
        }
        refresh()
        select(conversation.id)
        return conversation.id
    }

    /// Opens a conversation. Selecting the open one again keeps its session, including a reply in progress.
    /// Opening a local conversation closes the remote session shown in the detail pane.
    /// A conversation left while its reply was streaming opens on the same session, with the reply still
    /// arriving.
    public func select(_ id: UUID?) {
        if id != nil {
            closeRemote()
        }
        guard id != selectedID else { return }
        keepSessionIfLive()
        guard let id, (try? store.conversation(id: id)) != nil else {
            selectedID = nil
            session = nil
            return
        }
        selectedID = id
        session = liveSessions.removeValue(forKey: id)
            ?? ChatSession(service: service, model: model, store: store, conversationID: id)
    }

    /// Keeps the open local session if a reply is streaming in it, and drops kept sessions whose reply
    /// ended: the store holds all of their messages.
    private func keepSessionIfLive() {
        if let session, let selectedID, session.isBusy {
            liveSessions[selectedID] = session
        }
        liveSessions = liveSessions.filter { $0.value.isBusy }
    }

    /// Closes the remote session in the detail pane. It is kept if a reply is streaming in it; kept
    /// transcripts whose reply ended are dropped, the instance holds all of their messages.
    private func closeRemote() {
        if let openedRemote, openedRemote.isSending, !liveTranscripts.contains(where: { $0 === openedRemote }) {
            liveTranscripts.append(openedRemote)
        }
        openedRemote = nil
        liveTranscripts.removeAll { !$0.isSending }
    }

    /// Opens a session stored on the Hermes instance in the detail pane, in place of the local conversation.
    /// Does nothing when no instance is configured. A reply still running in a local conversation keeps running.
    /// A session left while its reply was streaming opens on the same transcript, with the reply still arriving.
    public func openRemote(_ session: RemoteSession) {
        guard let remoteSessions else { return }
        keepSessionIfLive()
        selectedID = nil
        self.session = nil
        // Selecting the open one again keeps its transcript, including a reply in progress. After a fork the
        // sidebar row carries the fork's id, which is the transcript's active session.
        guard openedRemote?.sessionID != session.id, openedRemote?.activeSessionID != session.id else { return }
        closeRemote()
        if let index = liveTranscripts.firstIndex(where: {
            $0.sessionID == session.id || $0.activeSessionID == session.id
        }) {
            // Not loaded again: the page would replace the lines, the reply being streamed included.
            openedRemote = liveTranscripts.remove(at: index)
            return
        }
        let transcript = remoteSessions.transcript(for: session)
        openedRemote = transcript
        // Loaded from here, not only from the view: on iOS 27 the detail view of a collapsed split view
        // can miss its `.task`, or have it cancelled at once, and the transcript would stay empty.
        Task { await transcript.load() }
    }

    /// The sidebar row currently open, as a `SidebarEntry.id`: the remote session if one is open,
    /// else the local conversation. A single selection drives navigation for both kinds of row.
    public var selectedEntryID: String? {
        if let openedRemote {
            // The active session: after a fork the sidebar row carries the fork's id.
            return SidebarEntry.remoteID(openedRemote.activeSessionID)
        }
        return selectedID.map(SidebarEntry.localID)
    }

    /// Opens the sidebar row with this `SidebarEntry.id`, local or remote. `nil` closes what is open,
    /// as when the navigation stack goes back to the list. An unknown id is ignored.
    public func selectEntry(_ entryID: String?) {
        guard let entryID else {
            closeRemote()
            select(nil)
            return
        }
        if let uuid = SidebarEntry.localUUID(from: entryID) {
            select(uuid)
        } else if let remoteID = SidebarEntry.remoteSessionID(from: entryID),
                  let remote = remoteSessions?.sessions.first(where: { $0.id == remoteID }) {
            openRemote(remote)
        }
    }

    /// Deletes a conversation. If it was open, the most recent remaining one opens; a new one is created if none is left.
    public func delete(_ id: UUID) throws {
        let wasSelected = id == selectedID
        if wasSelected {
            session?.stop()
        }
        liveSessions.removeValue(forKey: id)?.stop()
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

    /// The Markdown export of a conversation, or `nil` if it does not exist.
    public func export(_ id: UUID) -> ConversationExport? {
        guard let conversation = try? store.conversation(id: id) else { return nil }
        return ConversationExport.make(from: conversation)
    }

    /// Renames a conversation. Blank titles are ignored.
    public func rename(_ id: UUID, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try store.rename(conversation: id, to: trimmed)
        refresh()
    }
}
