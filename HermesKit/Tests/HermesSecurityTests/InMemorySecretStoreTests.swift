import Testing

@testable import HermesSecurity

@Suite("InMemorySecretStore")
struct InMemorySecretStoreTests {
    @Test("write, read and delete an entry")
    func roundTrip() throws {
        let store = InMemorySecretStore()
        #expect(try store.read(account: "api-key") == nil)

        try store.write("secret-value", account: "api-key")
        #expect(try store.read(account: "api-key") == "secret-value")

        try store.write("other", account: "api-key")
        #expect(try store.read(account: "api-key") == "other")

        try store.delete(account: "api-key")
        #expect(try store.read(account: "api-key") == nil)
    }
}
