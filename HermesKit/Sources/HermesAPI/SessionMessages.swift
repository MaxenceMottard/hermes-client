import Foundation

/// One page of `GET /api/sessions/{id}/messages`, in chronological order. Pages count back from the newest message.
public struct SessionMessagesPage: Sendable, Equatable {
    public let sessionID: String
    /// Messages as the instance sent them, compaction scaffolding included. Filtering is the caller's job.
    public let messages: [SessionMessage]
    /// Whether another page exists after this one.
    public let hasMore: Bool

    public init(sessionID: String, messages: [SessionMessage], hasMore: Bool) {
        self.sessionID = sessionID
        self.messages = messages
        self.hasMore = hasMore
    }
}

/// A message of a session stored on the Hermes instance. Only the fields a transcript needs are kept.
public struct SessionMessage: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let role: String
    /// `nil` or empty for rows that carry no text, such as tool calls or compaction markers. For a message
    /// stored as `text` and `image_url` parts, the text parts joined by new lines.
    public let content: String?
    public let timestamp: Date?
    /// `"hidden"` marks rows the instance wants clients not to display.
    public let displayKind: String?

    public init(
        id: String,
        role: String,
        content: String?,
        timestamp: Date? = nil,
        displayKind: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.displayKind = displayKind
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
        case displayKind = "display_kind"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The instance stores message ids as integers; a string is accepted too.
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        // A string, or an array of `text` and `image_url` parts (a multimodal message). Anything else
        // carries nothing to show.
        if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
            content = text
        } else if let parts = try? container.decodeIfPresent([ContentPartBody].self, forKey: .content) {
            let texts = parts.compactMap { $0.type == "text" ? $0.text : nil }
            content = texts.isEmpty ? nil : texts.joined(separator: "\n")
        } else {
            content = nil
        }
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp).map(Date.init(timeIntervalSince1970:))
        displayKind = try container.decodeIfPresent(String.self, forKey: .displayKind)
    }
}

/// One part of a multimodal message content. Unknown part types keep only their `type`.
private struct ContentPartBody: Decodable {
    let type: String
    let text: String?

    private enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        text = try? container.decodeIfPresent(String.self, forKey: .text)
    }
}

/// Body of `GET /api/sessions/{id}/messages`. Only `data` and the returned count are read.
struct SessionMessagesBody: Decodable, Sendable {
    var data: [SessionMessage]
    var returned: Int

    private enum CodingKeys: String, CodingKey {
        case data, pagination
    }

    private enum PaginationKeys: String, CodingKey {
        case returned
    }

    init(data: [SessionMessage], returned: Int) {
        self.data = data
        self.returned = returned
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([SessionMessage].self, forKey: .data)
        let pagination = try container.nestedContainer(keyedBy: PaginationKeys.self, forKey: .pagination)
        returned = try pagination.decode(Int.self, forKey: .returned)
    }
}
