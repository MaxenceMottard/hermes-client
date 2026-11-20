import Foundation
import Testing

@testable import HermesAPI

@Suite("Inline image attachments")
struct ImageAttachmentTests {
    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func messageObject(_ message: ChatMessage) throws -> [String: Any] {
        try jsonObject(JSONEncoder().encode(message))
    }

    @Test("only image MIME types with data are accepted")
    func rejectsNonImages() {
        #expect(ImageAttachment(mimeType: "image/jpeg", data: Data([1, 2])) != nil)
        #expect(ImageAttachment(mimeType: "application/pdf", data: Data([1, 2])) == nil)
        #expect(ImageAttachment(mimeType: "image/png", data: Data()) == nil)
    }

    @Test("the data URL is base64 with the MIME type")
    func dataURL() throws {
        let attachment = try #require(ImageAttachment(mimeType: "image/jpeg", data: Data("abc".utf8)))
        #expect(attachment.dataURL == "data:image/jpeg;base64,YWJj")
    }

    @Test("a text-only message keeps the plain string content")
    func textOnlyStaysString() throws {
        let object = try messageObject(ChatMessage(role: "user", content: "Hi"))
        #expect(Set(object.keys) == ["role", "content"])
        #expect(object["content"] as? String == "Hi")
    }

    @Test("a message with images encodes text and image_url parts in order")
    func multimodalParts() throws {
        let image = try #require(ImageAttachment(mimeType: "image/png", data: Data("abc".utf8)))
        let object = try messageObject(ChatMessage(role: "user", content: "What is this?", images: [image]))

        let parts = try #require(object["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0] as NSDictionary == ["type": "text", "text": "What is this?"] as NSDictionary)
        #expect(
            parts[1] as NSDictionary
                == ["type": "image_url", "image_url": ["url": "data:image/png;base64,YWJj"]] as NSDictionary)
    }

    @Test("an image without text omits the text part")
    func imageWithoutText() throws {
        let image = try #require(ImageAttachment(mimeType: "image/jpeg", data: Data([0xFF])))
        let object = try messageObject(ChatMessage(role: "user", content: "", images: [image]))

        let parts = try #require(object["content"] as? [[String: Any]])
        #expect(parts.count == 1)
        #expect(parts[0]["type"] as? String == "image_url")
    }

    @Test("decoding a message ignores images and reads the string content")
    func decodeDropsImages() throws {
        let json = Data(#"{"role":"assistant","content":"Hello"}"#.utf8)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(decoded == ChatMessage(role: "assistant", content: "Hello"))
    }
}
