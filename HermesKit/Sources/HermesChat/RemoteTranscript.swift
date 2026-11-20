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

    public nonisolated let sessionID: String
    public nonisolated let title: String?
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

    public init(sessionID: String, title: String?, source: any SessionListing) {
        self.sessionID = sessionID
        self.title = title
        self.source = source
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

    /// Loads the first page and replaces the transcript. Ignored while a request is running.
    public func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let page = try await source.listSessionMessages(
                sessionID: sessionID, limit: Self.pageSize, offset: 0
            )
            lines = Self.lines(from: page.messages)
            received = page.messages.count
            hasMore = page.hasMore
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(HermesAPIError.from(error))
        }
    }

    /// Prepends the next page of older messages, if the instance reported one.
    public func loadMore() async {
        guard hasMore, state != .loading else { return }
        state = .loading
        do {
            let page = try await source.listSessionMessages(
                sessionID: sessionID, limit: Self.pageSize, offset: received
            )
            lines = Self.lines(from: page.messages) + lines
            received += page.messages.count
            hasMore = page.hasMore
            state = .loaded
        } catch is CancellationError {
            state = .loaded
        } catch {
            state = .failed(HermesAPIError.from(error))
        }
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

    private func stream(_ message: String, replyID: String) async {
        do {
            for try await event in await source.streamSessionChat(sessionID: sessionID, message: message) {
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
