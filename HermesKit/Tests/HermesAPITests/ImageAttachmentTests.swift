import Foundation
import Testing

@testable import HermesAPI

@Suite("Inline image attachments")
struct ImageAttachmentTests {
    /// The JSON body of a session chat request carrying `text` and `images`.
    private func requestObject(_ text: String, images: [ImageAttachment] = []) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionChatRequest(message: MessageContent(text: text, images: images)))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
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

    @Test("a text-only message is sent as a plain string")
    func textOnlyStaysString() throws {
        let object = try requestObject("Hi")
        #expect(Set(object.keys) == ["message"])
        #expect(object["message"] as? String == "Hi")
    }

    @Test("a message with images is sent as text and image_url parts, in order")
    func multimodalParts() throws {
        let first = try #require(ImageAttachment(mimeType: "image/png", data: Data("abc".utf8)))
        let second = try #require(ImageAttachment(mimeType: "image/jpeg", data: Data([0xFF])))
        let object = try requestObject("What is this?", images: [first, second])

        let parts = try #require(object["message"] as? [[String: Any]])
        #expect(parts.count == 3)
        #expect(parts[0] as NSDictionary == ["type": "text", "text": "What is this?"] as NSDictionary)
        #expect(
            parts[1] as NSDictionary
                == ["type": "image_url", "image_url": ["url": "data:image/png;base64,YWJj"]] as NSDictionary)
        #expect(
            parts[2] as NSDictionary
                == ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,/w=="]] as NSDictionary)
    }

    @Test("an image without text omits the text part")
    func imageWithoutText() throws {
        let image = try #require(ImageAttachment(mimeType: "image/jpeg", data: Data([0xFF])))
        let object = try requestObject("", images: [image])

        let parts = try #require(object["message"] as? [[String: Any]])
        #expect(parts.count == 1)
        #expect(parts[0]["type"] as? String == "image_url")
    }
}
