import Testing
@testable import HermesStore

@Suite("HermesStoreModule")
struct HermesStoreModuleTests {
    @Test("le nom du module est stable")
    func moduleName() {
        #expect(HermesStoreModule.name == "HermesStore")
    }
}
