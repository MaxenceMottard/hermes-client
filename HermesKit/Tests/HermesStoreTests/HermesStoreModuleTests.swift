import Testing
@testable import HermesStore

@Suite("HermesStoreModule")
struct HermesStoreModuleTests {
    @Test("module name is stable")
    func moduleName() {
        #expect(HermesStoreModule.name == "HermesStore")
    }
}
