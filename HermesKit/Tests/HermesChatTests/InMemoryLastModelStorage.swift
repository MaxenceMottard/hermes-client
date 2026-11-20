import Foundation

@testable import HermesChat

/// Non-persistent storage for tests.
final class InMemoryLastModelStorage: LastModelStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var choice: ModelChoice?

    init(choice: ModelChoice? = nil) {
        self.choice = choice
    }

    func load() -> ModelChoice? {
        lock.lock()
        defer { lock.unlock() }
        return choice
    }

    func save(_ choice: ModelChoice) {
        lock.lock()
        defer { lock.unlock() }
        self.choice = choice
    }
}
