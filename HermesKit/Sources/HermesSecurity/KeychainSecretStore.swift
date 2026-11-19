#if canImport(Security)
    import Foundation
    import Security

    /// Keychain-backed secret store. Items are generic passwords scoped to `service`.
    ///
    /// With `synchronizable: true`, items sync through iCloud Keychain. Items are not synced otherwise.
    public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
        public enum Failure: Error, Equatable {
            /// A Keychain call failed with this status. The message never contains the secret.
            case status(OSStatus)
        }

        private let service: String
        private let synchronizable: Bool

        public init(service: String = HermesSecurityModule.keychainService, synchronizable: Bool = false) {
            self.service = service
            self.synchronizable = synchronizable
        }

        public func read(account: String) throws -> String? {
            var query = baseQuery(account: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound {
                return nil
            }
            guard status == errSecSuccess else {
                throw Failure.status(status)
            }
            guard let data = result as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }

        public func write(_ value: String, account: String) throws {
            let query = baseQuery(account: account)
            let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]

            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecSuccess {
                return
            }
            guard updateStatus == errSecItemNotFound else {
                throw Failure.status(updateStatus)
            }

            var addQuery = query
            addQuery[kSecValueData as String] = Data(value.utf8)
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Failure.status(addStatus)
            }
        }

        public func delete(account: String) throws {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw Failure.status(status)
            }
        }

        private func baseQuery(account: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: synchronizable,
            ]
        }
    }
#endif
