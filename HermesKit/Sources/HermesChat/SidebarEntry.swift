import Foundation
import HermesAPI
import HermesStore

/// One row of the sidebar: a conversation kept on this device, or a session stored on the Hermes instance.
public enum SidebarEntry: Identifiable, Equatable, Sendable {
    case local(ConversationSummary)
    case remote(RemoteSession)

    public var id: String {
        switch self {
        case .local(let summary): Self.localID(summary.id)
        case .remote(let session): Self.remoteID(session.id)
        }
    }

    private static let localPrefix = "local-"
    private static let remotePrefix = "remote-"

    /// The id of the row of a local conversation.
    public static func localID(_ id: UUID) -> String { localPrefix + id.uuidString }

    /// The id of the row of a remote session.
    public static func remoteID(_ sessionID: String) -> String { remotePrefix + sessionID }

    /// The conversation id in a local row id, or `nil` for any other id.
    public static func localUUID(from entryID: String) -> UUID? {
        guard entryID.hasPrefix(localPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(localPrefix.count)))
    }

    /// The session id in a remote row id, or `nil` for any other id.
    public static func remoteSessionID(from entryID: String) -> String? {
        guard entryID.hasPrefix(remotePrefix) else { return nil }
        let id = String(entryID.dropFirst(remotePrefix.count))
        return id.isEmpty ? nil : id
    }

    /// Last time the user interacted with the entry: the last update of a local conversation, or the
    /// last activity of a remote session (its start time when that is missing).
    public var lastInteraction: Date? {
        switch self {
        case .local(let summary): summary.updatedAt
        case .remote(let session): session.lastActive ?? session.startedAt
        }
    }

    /// Local conversations and remote sessions in one list, most recent interaction first.
    /// Entries without a date go last. Ties are broken by `id`, so the order is stable.
    public static func merged(local: [ConversationSummary], remote: [RemoteSession]) -> [SidebarEntry] {
        let entries = local.map(SidebarEntry.local) + remote.map(SidebarEntry.remote)
        return entries.sorted { lhs, rhs in
            switch (lhs.lastInteraction, rhs.lastInteraction) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.id < rhs.id
            }
        }
    }
}
