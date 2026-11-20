import Foundation
import HermesAPI
import HermesStore

#if !os(Linux)
    import Observation
#endif

/// The title shown for a conversation the instance has not named yet.
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

/// The conversation list and the open conversation.
///
/// Every conversation is a session stored on the Hermes instance: a new one is created there, and the
/// instance keeps its messages, title and model. The conversations saved on this device by earlier
/// versions of the app stay readable, and can be renamed, exported or deleted, but not continued: the
/// instance has no copy of them.
///
/// A session created here and left before any message is sent is deleted from the instance, so an
/// abandoned "New conversation" does not stay in the list.
///
/// `@Observable` is applied on Apple platforms, see `RemoteSessionList` for why it is left out on Linux.
@MainActor
#if !os(Linux)
    @Observable
#endif
public final class ConversationBrowser {
    /// The conversations saved on this device, most recent first.
    public private(set) var summaries: [ConversationSummary] = []
    /// The id of the open conversation saved on this device, or `nil`.
    public private(set) var selectedID: UUID?
    /// The open conversation saved on this device, read-only.
    public private(set) var archived: StoredConversation?
    /// The open session.
    public private(set) var openedRemote: RemoteTranscript?
    public let remoteSessions: RemoteSessionList
    /// `true` while a new session is being created on the instance.
    public private(set) var isCreating = false

    private let store: any ConversationStore
    private let model: String
    private let lastModel: (any LastModelStorage)?
    /// Sessions created here in which no message was sent yet.
    private var unsentSessionIDs: Set<String> = []
    /// Sessions left while a reply was streaming. The reply exists only in the transcript that sent the
    /// message: the instance offers no way to attach to a turn already running, so opening the session
    /// again shows that transcript instead of a page read from the instance.
    private var liveTranscripts: [RemoteTranscript] = []

    /// `model` is the instance default, used when no model was chosen yet.
    public init(
        store: any ConversationStore,
        remoteSessions: RemoteSessionList,
        model: String = ModelChoice.instanceDefault.model,
        lastModel: (any LastModelStorage)? = nil
    ) {
        self.store = store
        self.remoteSessions = remoteSessions
        self.model = model
        self.lastModel = lastModel
        refresh()
    }

    /// Reloads the list of conversations saved on this device.
    public func refresh() {
        if let loaded = try? store.summaries() {
            summaries = loaded
        }
    }

    /// The instance default model, the fallback of the new conversation screen.
    public var defaultChoice: ModelChoice {
        ModelChoice(model: model)
    }

    /// The model a new conversation starts on: the last one chosen, or the instance default.
    public var preferredChoice: ModelChoice {
        lastModel?.load() ?? defaultChoice
    }

    /// Creates a session on the instance and opens it. `chosen` is the model it runs on; `nil` or a
    /// blank model takes `preferredChoice`. A model chosen here is remembered for the next conversation.
    ///
    /// The instance default model is not sent: the instance picks its configured model.
    @discardableResult
    public func createConversation(model chosen: String? = nil, provider: String? = nil) async throws -> RemoteSession {
        let explicit = chosen.flatMap { ModelChoice(model: $0, provider: provider).normalized }
        let choice = explicit ?? preferredChoice
        let lock = choice == ModelChoice.instanceDefault ? nil : choice
        isCreating = true
        defer { isCreating = false }
        let session = try await remoteSessions.create(model: lock)
        if let explicit {
            lastModel?.save(explicit)
        }
        unsentSessionIDs.insert(session.id)
        closeOpened()
        let transcript = remoteSessions.transcript(for: session, model: choice)
        transcript.markEmpty()
        watch(transcript)
        openedRemote = transcript
        return session
    }

    /// Opens a conversation saved on this device, read-only, or closes the open one with `nil`.
    public func select(_ id: UUID?) {
        guard id != selectedID || id == nil else { return }
        closeOpened()
        guard let id, let conversation = try? store.conversation(id: id) else { return }
        selectedID = id
        archived = conversation
    }

    /// Opens a session. Selecting the open one again keeps its transcript, including a reply in progress.
    /// A session left while its reply was streaming opens on the same transcript, with the reply still arriving.
    public func openRemote(_ session: RemoteSession) {
        // After a fork the sidebar row carries the fork's id, which is the transcript's active session.
        if let openedRemote, openedRemote.sessionID == session.id || openedRemote.activeSessionID == session.id {
            return
        }
        closeOpened()
        if let index = liveTranscripts.firstIndex(where: {
            $0.sessionID == session.id || $0.activeSessionID == session.id
        }) {
            // Not loaded again: the page would replace the lines, the reply being streamed included.
            openedRemote = liveTranscripts.remove(at: index)
            return
        }
        let transcript = remoteSessions.transcript(for: session)
        watch(transcript)
        openedRemote = transcript
        // Loaded from here, not only from the view: on iOS 27 the detail view of a collapsed split view
        // can miss its `.task`, or have it cancelled at once, and the transcript would stay empty.
        Task { await transcript.load() }
    }

    /// The sidebar row of the open conversation.
    public var selectedEntryID: String? {
        if let openedRemote {
            // The active session: after a fork the sidebar row carries the fork's id.
            return SidebarEntry.remoteID(openedRemote.activeSessionID)
        }
        return selectedID.map(SidebarEntry.localID)
    }

    /// Opens the conversation of a sidebar row, or closes the open one with `nil`.
    public func selectEntry(_ entryID: String?) {
        guard let entryID else {
            closeOpened()
            return
        }
        if let uuid = SidebarEntry.localUUID(from: entryID) {
            select(uuid)
        } else if let remoteID = SidebarEntry.remoteSessionID(from: entryID),
                  let remote = remoteSessions.sessions.first(where: { $0.id == remoteID }) {
            openRemote(remote)
        }
    }

    /// Reloads the session list, then gives the open conversation its new title, if the instance named it.
    public func reloadSessions() async {
        await remoteSessions.reload()
        syncOpenedTitle()
    }

    // MARK: Sessions on the instance

    /// Renames a session on the instance. A blank title is ignored.
    public func renameSession(_ sessionID: String, to title: String) async throws {
        try await remoteSessions.rename(sessionID, to: title)
        syncOpenedTitle()
    }

    /// Deletes a session on the instance. The open one is stopped and closed first.
    public func deleteSession(_ sessionID: String) async throws {
        let isOpen = openedRemote.map { $0.sessionID == sessionID || $0.activeSessionID == sessionID } ?? false
        if isOpen {
            openedRemote?.stop()
        }
        if let index = liveTranscripts.firstIndex(where: {
            $0.sessionID == sessionID || $0.activeSessionID == sessionID
        }) {
            liveTranscripts.remove(at: index).stop()
        }
        try await remoteSessions.delete(sessionID)
        unsentSessionIDs.remove(sessionID)
        if isOpen {
            openedRemote = nil
        }
    }

    // MARK: Conversations saved on this device

    /// Deletes a conversation saved on this device, and closes it if it is open.
    public func delete(_ id: UUID) throws {
        try store.deleteConversation(id: id)
        if id == selectedID {
            selectedID = nil
            archived = nil
        }
        refresh()
    }

    /// The Markdown export of a conversation saved on this device.
    public func export(_ id: UUID) -> ConversationExport? {
        guard let conversation = try? store.conversation(id: id) else { return nil }
        return ConversationExport.make(from: conversation)
    }

    /// Renames a conversation saved on this device. A blank title is ignored.
    public func rename(_ id: UUID, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try store.rename(conversation: id, to: trimmed)
        refresh()
        if id == selectedID {
            archived = try? store.conversation(id: id)
        }
    }

    // MARK: Private

    /// Closes the open conversation. A session created here and left without a message is deleted. One
    /// left while a reply streams is kept; kept transcripts whose reply ended are dropped, the instance
    /// holds all of their messages.
    private func closeOpened() {
        selectedID = nil
        archived = nil
        defer { liveTranscripts.removeAll { !$0.isSending } }
        guard let transcript = openedRemote else { return }
        openedRemote = nil
        if transcript.isSending, !liveTranscripts.contains(where: { $0 === transcript }) {
            liveTranscripts.append(transcript)
        }
        let sessionID = transcript.activeSessionID
        guard unsentSessionIDs.remove(sessionID) != nil, !transcript.hasSent else { return }
        Task { try? await remoteSessions.delete(sessionID) }
    }

    /// Follows a reply: once it ends, the session is no longer unsent, and the list is reloaded so that the
    /// row moves up and shows the title the instance may have given it.
    private func watch(_ transcript: RemoteTranscript) {
        transcript.onReplyEnded = { [weak self, weak transcript] in
            guard let self, let transcript else { return }
            unsentSessionIDs.remove(transcript.activeSessionID)
            Task { await self.reloadSessions() }
        }
    }

    private func syncOpenedTitle() {
        guard let openedRemote,
              let session = remoteSessions.sessions.first(where: { $0.id == openedRemote.activeSessionID })
        else { return }
        openedRemote.update(from: session)
    }
}
