import Foundation
import HermesStore
import Testing

@testable import HermesChat

@MainActor
@Suite("Last used model")
struct LastModelStorageTests {
    private func makeBrowser(
        store: InMemoryConversationStore = InMemoryConversationStore(),
        lastModel: InMemoryLastModelStorage
    ) -> ConversationBrowser {
        ConversationBrowser(
            store: store,
            service: FakeChatService(scripts: []),
            model: "default-model",
            lastModel: lastModel
        )
    }

    @Test("with nothing saved, new conversations start on the default model")
    func defaultWhenNothingSaved() {
        let browser = makeBrowser(lastModel: InMemoryLastModelStorage())

        #expect(browser.preferredModel == "default-model")
        #expect(browser.session?.model == "default-model")
    }

    @Test("a chosen model is saved and becomes the preferred model")
    func chosenModelIsSaved() throws {
        let storage = InMemoryLastModelStorage()
        let browser = makeBrowser(lastModel: storage)

        try browser.createConversation(model: "other-model")

        #expect(storage.load() == "other-model")
        #expect(browser.preferredModel == "other-model")
    }

    @Test("the first conversation starts on the last used model")
    func firstConversationUsesLastModel() {
        let store = InMemoryConversationStore()
        let browser = makeBrowser(store: store, lastModel: InMemoryLastModelStorage(model: "saved-model"))

        #expect(browser.summaries.first?.model == "saved-model")
        #expect(browser.session?.model == "saved-model")
    }

    @Test("a conversation created without a choice uses the last model and saves nothing")
    func noChoiceUsesLastModel() throws {
        let storage = InMemoryLastModelStorage(model: "saved-model")
        let browser = makeBrowser(lastModel: storage)

        let id = try browser.createConversation()

        #expect(browser.summaries.first { $0.id == id }?.model == "saved-model")
        #expect(storage.load() == "saved-model")
    }

    @Test("UserDefaults storage keeps the model across instances and ignores blank values")
    func userDefaultsRoundTrip() throws {
        let suite = "LastModelStorageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(UserDefaultsLastModelStorage(defaults: defaults).load() == nil)

        UserDefaultsLastModelStorage(defaults: defaults).save("some-model")
        #expect(UserDefaultsLastModelStorage(defaults: defaults).load() == "some-model")

        defaults.set("   ", forKey: UserDefaultsLastModelStorage.key)
        #expect(UserDefaultsLastModelStorage(defaults: defaults).load() == nil)
    }
}
