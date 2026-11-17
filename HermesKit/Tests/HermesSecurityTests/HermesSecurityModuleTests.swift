import Testing

@testable import HermesSecurity

@Suite("HermesSecurityModule")
struct HermesSecurityModuleTests {
    @Test("Keychain service name contains no secret")
    func keychainServiceName() {
        #expect(HermesSecurityModule.keychainService == "hermes-client")
    }
}
