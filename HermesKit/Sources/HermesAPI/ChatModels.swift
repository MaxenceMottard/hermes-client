import Foundation

/// An image sent inline with a message. Sent as an `image_url` part holding a base64 data URL.
public struct ImageAttachment: Sendable, Equatable {
    public let mimeType: String
    public let data: Data

    /// Returns `nil` unless `mimeType` is an `image/*` type and `data` is not empty.
    public init?(mimeType: String, data: Data) {
        guard mimeType.lowercased().hasPrefix("image/"), !data.isEmpty else { return nil }
        self.mimeType = mimeType
        self.data = data
    }

    /// `data:<mime>;base64,<payload>`, the form the instance accepts for inline images.
    public var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

/// A message in a conversation. `role` stays a `String` so that roles unknown to the instance still decode.
///
/// Text-only messages are encoded with `content` as a plain string. A message with images is encoded
/// with `content` as an array of `text` and `image_url` parts, the OpenAI vision shape.
/// Decoding reads a string `content` only and never produces images.
public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: String
    public var content: String
    public var images: [ImageAttachment]

    public init(role: String, content: String, images: [ImageAttachment] = []) {
        self.role = role
        self.content = content
        self.images = images
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        images = []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if images.isEmpty {
            try container.encode(content, forKey: .content)
        } else {
            var parts: [ContentPart] = []
            if !content.isEmpty {
                parts.append(ContentPart(type: "text", text: content))
            }
            parts += images.map { ContentPart(type: "image_url", imageURL: ImageURLPart(url: $0.dataURL)) }
            try container.encode(parts, forKey: .content)
        }
    }
}

/// One element of a multimodal `content` array.
private struct ContentPart: Encodable {
    let type: String
    var text: String?
    var imageURL: ImageURLPart?

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct ImageURLPart: Encodable {
    let url: String
}

/// Body of `POST /v1/chat/completions`. Encodes exactly `model`, `messages` and `stream`.
public struct ChatRequest: Encodable, Sendable, Equatable {
    public var model: String
    public var messages: [ChatMessage]
    public var stream: Bool

    public init(model: String, messages: [ChatMessage], stream: Bool) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

/// Non-streamed response. Unknown fields are ignored when decoding.
public struct ChatCompletion: Codable, Sendable, Equatable {
    public var id: String?
    public var model: String
    public var choices: [Choice]

    public init(id: String?, model: String, choices: [Choice]) {
        self.id = id
        self.model = model
        self.choices = choices
    }

    public struct Choice: Codable, Sendable, Equatable {
        public var index: Int
        public var message: ChatMessage
        public var finishReason: String?

        public init(index: Int, message: ChatMessage, finishReason: String?) {
            self.index = index
            self.message = message
            self.finishReason = finishReason
        }

        private enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }
}

/// A chunk of an SSE stream (`data: {...}`). Unknown fields are ignored when decoding.
public struct ChatChunk: Codable, Sendable, Equatable {
    public var id: String?
    public var model: String?
    public var choices: [Choice]

    public init(id: String?, model: String?, choices: [Choice]) {
        self.id = id
        self.model = model
        self.choices = choices
    }

    /// Text added by this chunk, or `nil` if the chunk carries none.
    public var contentDelta: String? {
        choices.first?.delta.content
    }

    public struct Choice: Codable, Sendable, Equatable {
        public var index: Int
        public var delta: Delta
        public var finishReason: String?

        public init(index: Int, delta: Delta, finishReason: String?) {
            self.index = index
            self.delta = delta
            self.finishReason = finishReason
        }

        private enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    public struct Delta: Codable, Sendable, Equatable {
        public var role: String?
        public var content: String?

        public init(role: String?, content: String?) {
            self.role = role
            self.content = content
        }
    }
}
