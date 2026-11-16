import Testing

@testable import Hermes

@Suite("HermesApp")
struct HermesAppTests {
    @Test("Root view can be instantiated")
    @MainActor
    func contentViewBuilds() {
        _ = ContentView()
    }
}
