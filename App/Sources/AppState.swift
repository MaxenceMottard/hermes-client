import HermesAPI
import HermesChat
import HermesSecurity
import HermesStore
import Observation

/// Composition root: loads the saved settings, opens the conversation store, and builds the browser
/// once the configuration is complete.
@MainActor
@Observable
final class AppState {
    private(set) var settings: ConnectionSettings?
    private(set) var browser: ConversationBrowser?
    /// Lists the instance models for the new conversation screen. Set together with `browser`.
    private(set) var modelCatalog: (any ModelCatalog)?

    private let settingsStorage: any SettingsStorage
    private let secrets: any SecretStore
    private let store: any ConversationStore
    private static let apiKeyAccount = "api-key"

    init(
        settingsStorage: any SettingsStorage = UserDefaultsSettingsStorage(),
        secrets: any SecretStore = KeychainSecretStore(),
        store: any ConversationStore = AppState.makeDefaultStore()
    ) {
        self.settingsStorage = settingsStorage
        self.secrets = secrets
        self.store = store
        settings = settingsStorage.load()
        rebuildBrowser()
    }

    var apiKey: String? {
        try? secrets.read(account: Self.apiKeyAccount)
    }

    /// SwiftData when the container opens, otherwise an in-memory store so that the app still starts.
    static func makeDefaultStore() -> any ConversationStore {
        do {
            let container = try SwiftDataConversationStore.makeContainer()
            return SwiftDataConversationStore(container: container)
        } catch {
            return InMemoryConversationStore()
        }
    }

    /// Saves the settings and the key, then builds the browser. Throws if the key cannot be stored.
    func save(settings: ConnectionSettings, apiKey: String) throws {
        try secrets.write(apiKey, account: Self.apiKeyAccount)
        settingsStorage.save(settings)
        self.settings = settings
        rebuildBrowser()
    }

    private func rebuildBrowser() {
        guard let settings,
              settings.isValid,
              let baseURL = ConnectionSettings.parseBaseURL(settings.baseURLString),
              let key = apiKey, !key.isEmpty
        else {
            browser = nil
            modelCatalog = nil
            return
        }
        let client = HermesClient(configuration: HermesClientConfiguration(baseURL: baseURL, apiKey: key))
        let imageStore = DirectorySentImageStore.inCaches()
        browser = ConversationBrowser(
            store: store,
            service: client,
            remoteSessions: RemoteSessionList(source: client, imageStore: imageStore),
            lastModel: UserDefaultsLastModelStorage(),
            imageStore: imageStore
        )
        modelCatalog = client
    }
}
