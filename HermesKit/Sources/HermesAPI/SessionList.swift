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

    public init(
        id: String,
        title: String? = nil,
        preview: String? = nil,
        messageCount: Int? = nil,
        startedAt: Date? = nil,
        lastActive: Date? = nil,
        pinned: Bool = false,
        archived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.messageCount = messageCount
        self.startedAt = startedAt
        self.lastActive = lastActive
        self.pinned = pinned
        self.archived = archived
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, preview
        case messageCount = "message_count"
        case startedAt = "started_at"
        case lastActive = "last_active"
        case pinned, archived
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
    }

    /// The instance stores flags as SQLite integers (0/1); booleans are accepted too.
    private static func flag(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Bool {
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return flag
        }
        return ((try? container.decodeIfPresent(Int.self, forKey: key)) ?? 0) != 0
    }
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
