import Testing

@testable import Hermes

@Suite("HermesApp")
struct HermesAppTests {
    @Test("La vue racine s'instancie")
    @MainActor
    func contentViewBuilds() {
        _ = ContentView()
    }
}
