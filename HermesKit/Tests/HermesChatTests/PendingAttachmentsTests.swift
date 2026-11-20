import Foundation
import HermesAPI
import Testing

@testable import HermesChat

@Suite("Pending attachments")
struct PendingAttachmentsTests {
    private func image(_ byte: UInt8) throws -> ImageAttachment {
        try #require(ImageAttachment(mimeType: "image/jpeg", data: Data([byte])))
    }

    @Test("a new selection asks to load each item once")
    func loadsNewItemsOnce() {
        var pending = PendingAttachments<String>()

        #expect(pending.select(["a", "b"]) == ["a", "b"])
        // Still loading: not asked again.
        #expect(pending.select(["a", "b", "c"]) == ["c"])
    }

    @Test("images keep the selection order whatever order the loads finish in")
    func keepsSelectionOrder() throws {
        var pending = PendingAttachments<String>()
        _ = pending.select(["a", "b", "c"])

        pending.finishLoading("c", attachment: try image(3))
        pending.finishLoading("a", attachment: try image(1))
        pending.finishLoading("b", attachment: try image(2))

        #expect(pending.entries.map(\.id) == ["a", "b", "c"])
        #expect(pending.attachments == [try image(1), try image(2), try image(3)])
    }

    @Test("deselecting an item drops its image")
    func deselectDrops() throws {
        var pending = PendingAttachments<String>()
        _ = pending.select(["a", "b"])
        pending.finishLoading("a", attachment: try image(1))
        pending.finishLoading("b", attachment: try image(2))

        #expect(pending.select(["b"]).isEmpty)
        #expect(pending.entries.map(\.id) == ["b"])
    }

    @Test("an item deselected while it loads is not added")
    func deselectWhileLoading() throws {
        var pending = PendingAttachments<String>()
        _ = pending.select(["a"])
        _ = pending.select([])

        pending.finishLoading("a", attachment: try image(1))

        #expect(pending.isEmpty)
    }

    @Test("an unreadable image is dropped and can be loaded again when picked again")
    func failedLoad() throws {
        var pending = PendingAttachments<String>()
        _ = pending.select(["a"])

        pending.finishLoading("a", attachment: nil)

        #expect(pending.isEmpty)
        #expect(pending.select([]) == [])
        #expect(pending.select(["a"]) == ["a"])
    }

    @Test("removing an image returns the selection left for the picker")
    func removeReturnsSelection() throws {
        var pending = PendingAttachments<String>()
        _ = pending.select(["a", "b"])
        pending.finishLoading("a", attachment: try image(1))
        pending.finishLoading("b", attachment: try image(2))

        #expect(pending.remove("a") == ["b"])
        #expect(pending.entries.map(\.id) == ["b"])
        // The picker hands back the shorter selection: nothing to load.
        #expect(pending.select(["b"]).isEmpty)
    }

    @Test("clearing after a send ignores loads still in flight")
    func clearIgnoresInFlight() throws {
        var pending = PendingAttachments<String>()
        _ = pending.select(["a", "b"])
        pending.finishLoading("a", attachment: try image(1))

        pending.clear()
        pending.finishLoading("b", attachment: try image(2))

        #expect(pending.isEmpty)
    }
}
