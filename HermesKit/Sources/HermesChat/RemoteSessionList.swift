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
    func forkSession(sessionID: String) async throws -> RemoteSession
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
    private let imageStore: (any SentImageStore)?
    /// Number of unpinned rows received so far, which is the offset of the next page.
    private var windowOffset = 0

    /// `imageStore` holds the images sent from this device: transcripts show them in place of the markers
    /// the instance stores.
    public init(source: any SessionListing, imageStore: (any SentImageStore)? = nil) {
        self.source = source
        self.imageStore = imageStore
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

    /// The messages of one session, loaded on demand by the transcript view. When the transcript moves
    /// to a fork to accept a message, the fork takes the original's row.
    public func transcript(for session: RemoteSession) -> RemoteTranscript {
        let transcript = RemoteTranscript(
            sessionID: session.id,
            title: session.title,
            model: session.model,
            source: source,
            acceptsMessages: session.acceptsAPIMessages,
            imageStore: imageStore
        )
        transcript.onFork = { [weak self] fork in
            self?.replace(session.id, with: fork)
        }
        return transcript
    }

    /// Puts `session` in place of the row with id `originalID`, or at the top if that row is gone.
    func replace(_ originalID: String, with session: RemoteSession) {
        sessions.removeAll { $0.id == session.id }
        if let index = sessions.firstIndex(where: { $0.id == originalID }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }
}
