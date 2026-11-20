import Foundation
import HermesAPI

#if !os(Linux)
    import Observation
#endif

/// One message of a transcript: a user or assistant message with text, ready to show.
public struct TranscriptLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: String
    public let text: String
    public let date: Date?

    public init(id: String, role: String, text: String, date: Date?) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

/// The messages of a session stored on the Hermes instance, and a way to continue it.
///
/// Only user and assistant messages with text are kept. Tool, system and compaction rows, and rows the
/// instance marks as hidden, are dropped. The first page holds the newest messages; each further page holds
/// older ones and is put above the lines already shown. Pages are requested with an offset counted in
/// received messages, not in displayed lines.
///
/// `send(_:)` posts a message to the session and shows the reply as it streams. Its lines live only in
/// this object until the transcript is loaded again.
///
/// The instance refuses API messages in a session created elsewhere (web dashboard, TUI). For such a
/// session the first `send(_:)` forks it into an API session, which holds the same messages, and the
/// transcript continues in the fork: `activeSessionID` changes, `sessionID` does not.
///
/// `@Observable` is applied on Apple platforms, see `ChatSession` for why it is left out on Linux.
@MainActor
#if !os(Linux)
    @Observable
#endif
public final class RemoteTranscript: Identifiable {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(HermesAPIError)
    }

    /// Page size requested from the instance.
    public static let pageSize = 200

    /// The session this transcript was opened on. Stays the same after a fork.
    public nonisolated let sessionID: String
    public nonisolated let title: String?
    /// The session that messages are read from and sent to: `sessionID`, or its fork once one was made.
    public private(set) var activeSessionID: String
    /// `false` while the active session refuses API messages: the next `send(_:)` forks it first.
    public private(set) var acceptsMessages: Bool
    /// Called on the main actor with the new session after a fork.
    var onFork: (@MainActor (RemoteSession) -> Void)?
    public private(set) var lines: [TranscriptLine] = []
    public private(set) var state: State = .idle
    public private(set) var hasMore = false
    /// `true` while a reply is streaming.
    public private(set) var isSending = false
    /// Why the last message got no reply, or `nil`.
    public private(set) var sendError: String?

    private let source: any SessionListing
    /// Messages received so far, displayed or not: the offset of the next page.
    private var received = 0
    private var sendTask: Task<Void, Never>?
    /// The page request in flight, shared by every caller of `load()` and `loadMore()`.
    private var loadTask: Task<Void, Never>?

    public init(sessionID: String, title: String?, source: any SessionListing, acceptsMessages: Bool = true) {
        self.sessionID = sessionID
        self.title = title
        self.source = source
        self.activeSessionID = sessionID
        self.acceptsMessages = acceptsMessages
    }

    public nonisolated var id: String { sessionID }

    /// Keeps the lines a reader should see, in the order the instance returned them.
    public static func lines(from messages: [SessionMessage]) -> [TranscriptLine] {
        messages.compactMap { message in
            guard message.displayKind != "hidden",
                  message.role == "user" || message.role == "assistant",
                  let text = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            return TranscriptLine(id: message.id, role: message.role, text: text, date: message.timestamp)
        }
    }

    /// Loads the first page and replaces the transcript. A call made while a page is loading waits for it.
    ///
    /// The request runs in a task this object owns, so cancelling the caller does not cancel it. On iOS 27
    /// a collapsed split view can send the detail view `onDisappear` right after it appears, which cancels
    /// the view's `.task`: the request must outlive it, or the transcript stays empty.
    public func load() async {
        await run { transcript in
            let page = try await transcript.source.listSessionMessages(
                sessionID: transcript.activeSessionID, limit: Self.pageSize, offset: 0
            )
            transcript.lines = Self.lines(from: page.messages)
            transcript.received = page.messages.count
            transcript.hasMore = page.hasMore
        }
    }

    /// Prepends the next page of older messages, if the instance reported one. A call made while a page
    /// is loading waits for it.
    public func loadMore() async {
        guard hasMore || loadTask != nil else { return }
        await run { transcript in
            guard transcript.hasMore else { return }
            let page = try await transcript.source.listSessionMessages(
                sessionID: transcript.activeSessionID, limit: Self.pageSize, offset: transcript.received
            )
            transcript.lines = Self.lines(from: page.messages) + transcript.lines
            transcript.received += page.messages.count
            transcript.hasMore = page.hasMore
        }
    }

    /// Runs one page request in a task owned by this object, or waits for the one already running.
    private func run(_ request: @escaping @MainActor (RemoteTranscript) async throws -> Void) async {
        if let loadTask {
            await loadTask.value
            return
        }
        state = .loading
        let task = Task { @MainActor in
            do {
                try await request(self)
                self.state = .loaded
            } catch is CancellationError {
                self.state = self.lines.isEmpty ? .idle : .loaded
            } catch {
                self.state = .failed(HermesAPIError.from(error))
            }
            self.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    /// Sends a message to the session and shows the reply as it streams. The user line appears at once.
    /// Blank text is ignored, and so is a call made while a reply is still streaming.
    public func send(_ text: String) async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else { return }
        isSending = true
        sendError = nil
        lines.append(TranscriptLine(id: "local-user-\(UUID().uuidString)", role: "user", text: message, date: Date()))
        let replyID = "local-assistant-\(UUID().uuidString)"
        lines.append(TranscriptLine(id: replyID, role: "assistant", text: "", date: nil))

        let task = Task { await self.stream(message, replyID: replyID) }
        sendTask = task
        await task.value
        sendTask = nil
        isSending = false
    }

    /// Stops the reply being streamed. The text received so far stays in the transcript.
    public func stop() {
        sendTask?.cancel()
    }

    /// Forks the active session so that it accepts API messages. Returns `false`, with `sendError` set,
    /// if the fork failed or was cancelled.
    private func forkIfNeeded() async -> Bool {
        guard !acceptsMessages else { return true }
        do {
            let fork = try await source.forkSession(sessionID: activeSessionID)
            activeSessionID = fork.id
            acceptsMessages = true
            onFork?(fork)
            return true
        } catch is CancellationError {
            return false
        } catch {
            let reason = HermesAPIError.from(error).errorDescription ?? "The request failed."
            sendError = "This conversation was started outside the app and could not be continued here. \(reason)"
            return false
        }
    }

    private func stream(_ message: String, replyID: String) async {
        guard await forkIfNeeded() else {
            lines.removeAll { $0.id == replyID }
            return
        }
        do {
            for try await event in await source.streamSessionChat(sessionID: activeSessionID, message: message) {
                switch event {
                case .delta(let delta):
                    setReply(id: replyID) { $0 + delta }
                case .completed(let content):
                    if !content.isEmpty {
                        setReply(id: replyID) { _ in content }
                    }
                case .failed(let reason):
                    sendError = reason
                case .finished:
                    break
                }
            }
        } catch is CancellationError {
            // Stopped by the user: keep what was received.
        } catch {
            sendError = HermesAPIError.from(error).errorDescription ?? "The message could not be sent."
        }
        if let index = lines.firstIndex(where: { $0.id == replyID }), lines[index].text.isEmpty {
            lines.remove(at: index)
        }
    }

    private func setReply(id: String, _ update: (String) -> String) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        let line = lines[index]
        lines[index] = TranscriptLine(id: line.id, role: line.role, text: update(line.text), date: line.date)
    }
}
