import Foundation

/// One page of `GET /api/sessions`.
public struct SessionPage: Sendable, Equatable {
    /// Sessions in the order the instance returned them (most recently active first).
    public let sessions: [RemoteSession]
    /// Whether another page exists after this one.
    public let hasMore: Bool

    public init(sessions: [RemoteSession], hasMore: Bool) {
        self.sessions = sessions
        self.hasMore = hasMore
    }
}

/// A Hermes session as listed by the instance. Only the fields the client shows are kept;
/// unknown fields are ignored. Every field except `id` may be absent.
public struct RemoteSession: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let title: String?
    public let preview: String?
    public let messageCount: Int?
    public let startedAt: Date?
    public let lastActive: Date?
    public let pinned: Bool
    public let archived: Bool
    /// Where the session was created: `api_server` for this app and other API clients, `local` for the
    /// web dashboard, `tui`, `cli`, a messaging platform, and so on. `nil` when the instance does not say.
    public let source: String?
    /// The model the session runs on, as the instance names it. `nil` when the instance does not say.
    public let model: String?

    public init(
        id: String,
        title: String? = nil,
        preview: String? = nil,
        messageCount: Int? = nil,
        startedAt: Date? = nil,
        lastActive: Date? = nil,
        pinned: Bool = false,
        archived: Bool = false,
        source: String? = nil,
        model: String? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.messageCount = messageCount
        self.startedAt = startedAt
        self.lastActive = lastActive
        self.pinned = pinned
        self.archived = archived
        self.source = source
        self.model = model
    }

    /// Whether the API accepts new messages in this session. The instance refuses API messages in a
    /// session another surface created (dashboard, TUI, messaging platform) with `permission_denied`:
    /// such a session must be forked first. A session without a source is assumed to accept them.
    public var acceptsAPIMessages: Bool {
        source == nil || source == Self.apiSource
    }

    /// The source of sessions created through the API.
    public static let apiSource = "api_server"

    private enum CodingKeys: String, CodingKey {
        case id, title, preview
        case messageCount = "message_count"
        case startedAt = "started_at"
        case lastActive = "last_active"
        case pinned, archived, source, model
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)
        // The instance sends Unix timestamps in seconds.
        startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt).map(Date.init(timeIntervalSince1970:))
        lastActive = try container.decodeIfPresent(Double.self, forKey: .lastActive).map(Date.init(timeIntervalSince1970:))
        pinned = Self.flag(in: container, forKey: .pinned)
        archived = Self.flag(in: container, forKey: .archived)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        model = try container.decodeIfPresent(String.self, forKey: .model)
    }

    /// The instance stores flags as SQLite integers (0/1); booleans are accepted too.
    private static func flag(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Bool {
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return flag
        }
        return ((try? container.decodeIfPresent(Int.self, forKey: key)) ?? 0) != 0
    }
}

/// Body of `POST /api/sessions/{id}/fork`: the new session.
struct SessionForkBody: Decodable, Sendable {
    var session: RemoteSession
}

/// Body of `GET /api/sessions`. Only the fields needed for the list are read.
struct SessionListBody: Decodable, Sendable {
    var data: [RemoteSession]
    var hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}
