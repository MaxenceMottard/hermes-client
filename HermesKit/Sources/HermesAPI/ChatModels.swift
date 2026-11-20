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

/// A message as a conversation screen shows it. `role` stays a `String` so that roles unknown to the
/// instance are kept.
public struct ChatMessage: Sendable, Equatable {
    public var role: String
    public var content: String
    /// Images sent with the message from this device, shown as thumbnails.
    public var images: [ImageAttachment]

    public init(role: String, content: String, images: [ImageAttachment] = []) {
        self.role = role
        self.content = content
        self.images = images
    }
}

/// The `content` of a user message sent to the instance.
///
/// Text alone is encoded as a plain string. With images, it is an array of `text` and `image_url`
/// parts, the OpenAI vision shape: the text first when there is any, then the images in order.
struct MessageContent: Encodable, Sendable, Equatable {
    let text: String
    let images: [ImageAttachment]

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        guard !images.isEmpty else {
            try container.encode(text)
            return
        }
        var parts: [ContentPart] = []
        if !text.isEmpty {
            parts.append(ContentPart(type: "text", text: text))
        }
        parts += images.map { ContentPart(type: "image_url", imageURL: ImageURLPart(url: $0.dataURL)) }
        try container.encode(parts)
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
