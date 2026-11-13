import Testing
@testable import HermesSecurity

@Suite("HermesSecurityModule")
struct HermesSecurityModuleTests {
    @Test("le service Keychain ne contient aucun secret")
    func keychainServiceName() {
        #expect(HermesSecurityModule.keychainService == "hermes-client")
    }
}
