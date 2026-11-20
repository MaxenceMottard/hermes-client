import Foundation

/// Storage for secrets such as the API key. The app uses `KeychainSecretStore`.
public protocol SecretStore: Sendable {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}
