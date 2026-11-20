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

/// The messages of a session stored on the Hermes instance, read-only.
///
/// Only user and assistant messages with text are kept. Tool, system and compaction rows, and rows the
/// instance marks as hidden, are dropped. Pages are requested with an offset counted in received
/// messages, not in displayed lines.
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

    private let source: any SessionListing
    /// Messages received so far, displayed or not: the offset of the next page.
    private var received = 0

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

    /// Appends the next page, if the instance reported one.
    public func loadMore() async {
        guard hasMore, state != .loading else { return }
        state = .loading
        do {
            let page = try await source.listSessionMessages(
                sessionID: sessionID, limit: Self.pageSize, offset: received
            )
            lines += Self.lines(from: page.messages)
            received += page.messages.count
            hasMore = page.hasMore
            state = .loaded
        } catch is CancellationError {
            state = .loaded
        } catch {
            state = .failed(HermesAPIError.from(error))
        }
    }
}
