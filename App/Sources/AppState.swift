import HermesAPI
import HermesChat
import HermesSecurity
import Observation

/// Composition root: loads the saved settings and builds the chat session once the configuration is complete.
@MainActor
@Observable
final class AppState {
    private(set) var settings: ConnectionSettings?
    private(set) var session: ChatSession?

    private let settingsStorage: any SettingsStorage
    private let secrets: any SecretStore
    private static let apiKeyAccount = "api-key"

    init(
        settingsStorage: any SettingsStorage = UserDefaultsSettingsStorage(),
        secrets: any SecretStore = InMemorySecretStore()
    ) {
        self.settingsStorage = settingsStorage
        self.secrets = secrets
        settings = settingsStorage.load()
        rebuildSession()
    }

    var apiKey: String? {
        try? secrets.read(account: Self.apiKeyAccount)
    }

    /// Saves the settings and the key, then builds the session. Throws if the key cannot be stored.
    func save(settings: ConnectionSettings, apiKey: String) throws {
        try secrets.write(apiKey, account: Self.apiKeyAccount)
        settingsStorage.save(settings)
        self.settings = settings
        rebuildSession()
    }

    private func rebuildSession() {
        guard let settings,
              settings.isValid,
              let baseURL = ConnectionSettings.parseBaseURL(settings.baseURLString),
              let key = apiKey, !key.isEmpty
        else {
            session = nil
            return
        }
        let client = HermesClient(configuration: HermesClientConfiguration(baseURL: baseURL, apiKey: key))
        session = ChatSession(service: client, model: settings.model)
    }
}
