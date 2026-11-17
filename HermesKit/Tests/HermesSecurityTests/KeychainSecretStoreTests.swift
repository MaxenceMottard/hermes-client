#if canImport(Security)
    import Foundation
    import Testing
    @testable import HermesSecurity

    /// Runs against the real Keychain, under a unique service name that is removed afterwards.
    /// Keychain access may be unavailable in some sandboxes; these tests are meant for macOS CI and devices.
    @Suite("KeychainSecretStore")
    struct KeychainSecretStoreTests {
        private func makeStore() -> (KeychainSecretStore, String) {
            let service = "dev.hermes.tests.\(UUID().uuidString)"
            return (KeychainSecretStore(service: service), service)
        }

        @Test("write, read, overwrite and delete an item")
        func roundTrip() throws {
            let (store, _) = makeStore()
            let account = "api-key"
            defer { try? store.delete(account: account) }

            #expect(try store.read(account: account) == nil)

            try store.write("first", account: account)
            #expect(try store.read(account: account) == "first")

            try store.write("second", account: account)
            #expect(try store.read(account: account) == "second")

            try store.delete(account: account)
            #expect(try store.read(account: account) == nil)
        }

        @Test("deleting a missing item is not an error")
        func deleteMissingItem() throws {
            let (store, _) = makeStore()
            try store.delete(account: "absent")
        }
    }
#endif
