import Foundation

/// Remembers the model chosen for the last new conversation, so that the next one starts on it.
public protocol LastModelStorage: Sendable {
    /// The last model saved, or `nil` if none was saved yet.
    func load() -> ModelChoice?
    func save(_ choice: ModelChoice)
}

/// `UserDefaults`-backed storage. A model name is not a secret.
public final class UserDefaultsLastModelStorage: LastModelStorage, @unchecked Sendable {
    static let modelKey = "lastUsedModel"
    static let providerKey = "lastUsedProvider"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ModelChoice? {
        guard let model = defaults.string(forKey: Self.modelKey) else { return nil }
        return ModelChoice(model: model, provider: defaults.string(forKey: Self.providerKey)).normalized
    }

    public func save(_ choice: ModelChoice) {
        defaults.set(choice.model, forKey: Self.modelKey)
        if let provider = choice.provider {
            defaults.set(provider, forKey: Self.providerKey)
        } else {
            defaults.removeObject(forKey: Self.providerKey)
        }
    }
}

/// Non-persistent storage. Used by tests and previews.
public final class InMemoryLastModelStorage: LastModelStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var choice: ModelChoice?

    public init(choice: ModelChoice? = nil) {
        self.choice = choice
    }

    public func load() -> ModelChoice? {
        lock.lock()
        defer { lock.unlock() }
        return choice
    }

    public func save(_ choice: ModelChoice) {
        lock.lock()
        defer { lock.unlock() }
        self.choice = choice
    }
}
