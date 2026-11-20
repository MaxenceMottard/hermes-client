#if canImport(SwiftData)
    import Foundation
    import Testing

    @testable import HermesStore

    @MainActor
    @Suite("SwiftDataConversationStore")
    struct SwiftDataConversationStoreTests {
        /// The app builds the store from a container it does not keep. The store must retain it,
        /// otherwise the first save traps inside SwiftData.
        private func makeStore() throws -> SwiftDataConversationStore {
            SwiftDataConversationStore(container: try SwiftDataConversationStore.makeContainer(inMemory: true))
        }

        @Test("works after the caller releases the container")
        func outlivesContainerReference() throws {
            let store = try makeStore()

            let created = try store.createConversation(title: "First")
            try store.replaceMessages([StoredMessage(role: "user", content: "hi")], inConversation: created.id)

            let loaded = try #require(try store.conversation(id: created.id))
            #expect(loaded.title == "First")
            #expect(loaded.messages == [StoredMessage(role: "user", content: "hi")])
            #expect(try store.summaries().map(\.id) == [created.id])
        }

        @Test("the model is saved with the conversation and shown in its summary")
        func keepsModel() throws {
            let store = try makeStore()
            let created = try store.createConversation(title: "First", model: "some-model")

            #expect(try store.conversation(id: created.id)?.model == "some-model")
            #expect(try store.summaries().first?.model == "some-model")
        }

        @Test("rename and delete")
        func renameAndDelete() throws {
            let store = try makeStore()
            let created = try store.createConversation(title: "First")

            try store.rename(conversation: created.id, to: "Renamed")
            #expect(try store.summaries().first?.title == "Renamed")

            try store.deleteConversation(id: created.id)
            #expect(try store.summaries().isEmpty)
        }
    }
#endif
