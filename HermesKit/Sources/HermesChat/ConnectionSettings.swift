import Foundation

/// Non-secret connection settings. The API key is stored separately, in a `SecretStore`.
public struct ConnectionSettings: Codable, Equatable, Sendable {
    public var baseURLString: String
    public var model: String

    public init(baseURLString: String, model: String) {
        self.baseURLString = baseURLString
        self.model = model
    }

    /// The base URL if the text is an absolute http(s) URL with a host, otherwise `nil`.
    public static func parseBaseURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        else {
            return nil
        }
        return url
    }

    /// `true` when the URL parses and the model name is not empty.
    public var isValid: Bool {
        Self.parseBaseURL(baseURLString) != nil && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Persistence of the non-secret settings.
public protocol SettingsStorage: Sendable {
    func load() -> ConnectionSettings?
    func save(_ settings: ConnectionSettings)
}

/// `UserDefaults`-backed storage. Only non-secret values belong here.
public final class UserDefaultsSettingsStorage: SettingsStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "connectionSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ConnectionSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ConnectionSettings.self, from: data)
    }

    public func save(_ settings: ConnectionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
