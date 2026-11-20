import Foundation

/// Remembers the model chosen for the last new conversation, so that the next one starts on it.
public protocol LastModelStorage: Sendable {
    /// The last model saved, or `nil` if none was saved yet.
    func load() -> String?
    func save(_ model: String)
}

/// `UserDefaults`-backed storage. A model name is not a secret.
public final class UserDefaultsLastModelStorage: LastModelStorage, @unchecked Sendable {
    static let key = "lastUsedModel"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> String? {
        guard let model = defaults.string(forKey: Self.key)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !model.isEmpty
        else { return nil }
        return model
    }

    public func save(_ model: String) {
        defaults.set(model, forKey: Self.key)
    }
}

/// Non-persistent storage. Used by tests and previews.
public final class InMemoryLastModelStorage: LastModelStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var model: String?

    public init(model: String? = nil) {
        self.model = model
    }

    public func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return model
    }

    public func save(_ model: String) {
        lock.lock()
        defer { lock.unlock() }
        self.model = model
    }
}
