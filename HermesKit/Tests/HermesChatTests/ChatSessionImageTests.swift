import Foundation
import HermesAPI
import Testing

@testable import HermesChat

@MainActor
@Suite("ChatSession with images")
struct ChatSessionImageTests {
    private func image(_ byte: UInt8) throws -> ImageAttachment {
        try #require(ImageAttachment(mimeType: "image/jpeg", data: Data([byte])))
    }

    @Test("a send with text and an image keeps the image on the user message and in the request")
    func imageIsSent() async throws {
        let service = FakeChatService(scripts: [.deltas(["A"])])
        let session = ChatSession(service: service, model: "m")
        let photo = try image(1)

        await session.send("Describe", images: [photo])

        #expect(session.messages.first == ChatMessage(role: "user", content: "Describe", images: [photo]))
        #expect(service.recordedRequests().first == [ChatMessage(role: "user", content: "Describe", images: [photo])])
    }

    @Test("images sent are copied to the image store, under the digest of their bytes")
    func imagesAreKept() async throws {
        let service = FakeChatService(scripts: [.deltas(["A"])])
        let store = InMemorySentImageStore()
        let session = ChatSession(service: service, model: "m", imageStore: store)
        let photo = try image(7)

        await session.send("Look", images: [photo])

        #expect(store.image(sha256: sha256Hex(photo.data)) == photo)
    }

    @Test("an image alone is a valid message")
    func imageWithoutText() async throws {
        let service = FakeChatService(scripts: [.deltas(["A"])])
        let session = ChatSession(service: service, model: "m")

        await session.send("  ", images: [try image(1)])

        #expect(session.messages.first?.content == "")
        #expect(session.messages.first?.images.count == 1)
        #expect(service.recordedRequests().count == 1)
    }

    @Test("more than the maximum number of images is rejected without sending")
    func tooManyImages() async throws {
        let service = FakeChatService(scripts: [])
        let session = ChatSession(service: service, model: "m")
        let photos = try (0...ChatSession.maxImagesPerMessage).map { try image(UInt8($0)) }

        await session.send("Too many", images: photos)

        #expect(session.messages.isEmpty)
        #expect(service.recordedRequests().isEmpty)
    }
}
