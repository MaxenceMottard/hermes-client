import Foundation
import HermesAPI

#if !os(Linux)
    import Observation
#endif

/// Source of the Hermes session list. `HermesClient` conforms; tests provide a fake.
public protocol SessionListing: Sendable {
    func listSessions(limit: Int, offset: Int) async throws -> SessionPage
    func listSessionMessages(sessionID: String, limit: Int, offset: Int) async throws -> SessionMessagesPage
    func streamSessionChat(sessionID: String, message: String) async -> AsyncThrowingStream<SessionChatEvent, any Error>
}

extension HermesClient: SessionListing {}

/// The sessions stored on the Hermes instance, shown next to the local conversations.
///
/// Pages are requested with an offset. The instance back-fills pinned sessions past the limit, so the
/// offset counts only the unpinned rows received; counting every row would skip some of them.
///
/// `@Observable` is applied on Apple platforms, see `ChatSession` for why it is left out on Linux.
@MainActor
#if !os(Linux)
    @Observable
#endif
public final class RemoteSessionList {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(HermesAPIError)
    }

    /// Page size requested from the instance.
    public static let pageSize = 50

    public private(set) var sessions: [RemoteSession] = []
    public private(set) var state: State = .idle
    public private(set) var hasMore = false

    private let source: any SessionListing
    /// Number of unpinned rows received so far, which is the offset of the next page.
    private var windowOffset = 0

    public init(source: any SessionListing) {
        self.source = source
    }

    public var isLoading: Bool {
        state == .loading
    }

    /// Loads the first page and replaces the list. Ignored while a request is running.
    public func reload() async {
        guard !isLoading else { return }
        state = .loading
        do {
            let page = try await source.listSessions(limit: Self.pageSize, offset: 0)
            sessions = page.sessions
            windowOffset = page.sessions.filter { !$0.pinned }.count
            hasMore = page.hasMore
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(HermesAPIError.from(error))
        }
    }

    /// Appends the next page, if the instance reported one. Sessions already listed are not repeated.
    public func loadNextPage() async {
        guard hasMore, !isLoading else { return }
        state = .loading
        do {
            let page = try await source.listSessions(limit: Self.pageSize, offset: windowOffset)
            let known = Set(sessions.map(\.id))
            sessions += page.sessions.filter { !known.contains($0.id) }
            windowOffset += page.sessions.filter { !$0.pinned }.count
            hasMore = page.hasMore
            state = .loaded
        } catch is CancellationError {
            state = .loaded
        } catch {
            state = .failed(HermesAPIError.from(error))
        }
    }

    /// The messages of one session, loaded on demand by the transcript view.
    public func transcript(for session: RemoteSession) -> RemoteTranscript {
        RemoteTranscript(sessionID: session.id, title: session.title, source: source)
    }
}
