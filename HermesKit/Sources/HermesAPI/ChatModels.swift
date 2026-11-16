/// A message in a conversation. `role` stays a `String` so that roles unknown to the instance still decode.
public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
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
