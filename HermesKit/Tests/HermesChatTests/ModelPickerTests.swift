import Foundation
import HermesAPI
import Testing

@testable import HermesChat

/// Returns a fixed listing, or throws the given error.
struct FakeModelCatalog: ModelCatalog {
    var result: ModelListResult = .models([])
    var error: (any Error)?

    func listModels() async throws -> ModelListResult {
        if let error {
            throw error
        }
        return result
    }
}

@MainActor
@Suite("ModelPicker")
struct ModelPickerTests {
    @Test("the preferred model stays selected when the instance lists it")
    func keepsListedPreferred() async {
        let picker = ModelPicker(catalog: FakeModelCatalog(result: .models(["a", "b"])), preferred: "b")
        #expect(picker.state == .loading)

        await picker.load()

        #expect(picker.state == .list(["a", "b"]))
        #expect(picker.selection == "b")
        #expect(picker.chosenModel == "b")
    }

    @Test("the first listed model is selected when the preferred one is not listed")
    func selectsFirstWhenPreferredMissing() async {
        let picker = ModelPicker(catalog: FakeModelCatalog(result: .models(["a", "b"])), preferred: "gone")

        await picker.load()

        #expect(picker.selection == "a")
    }

    @Test("a failed listing switches to manual entry with the preferred model filled in")
    func fallbackIsManual() async {
        let picker = ModelPicker(catalog: FakeModelCatalog(result: .fallback(.invalidResponse)), preferred: "p")

        await picker.load()

        #expect(picker.state == .manual(.invalidResponse))
        #expect(picker.selection == "p")
    }

    @Test("without a catalog the picker starts in manual entry")
    func noCatalogIsManual() async {
        let picker = ModelPicker(catalog: nil, preferred: "p")
        #expect(picker.state == .manual(nil))

        await picker.load()

        #expect(picker.state == .manual(nil))
    }

    @Test("a cancelled load leaves the picker loading")
    func cancelledLoadKeepsState() async {
        let picker = ModelPicker(catalog: FakeModelCatalog(error: CancellationError()), preferred: "p")

        await picker.load()

        #expect(picker.state == .loading)
        #expect(picker.selection == "p")
    }

    @Test("the chosen model is trimmed, and nil when blank")
    func chosenModelTrims() {
        let picker = ModelPicker(catalog: nil, preferred: "  m  ")
        #expect(picker.chosenModel == "m")

        picker.selection = "   "
        #expect(picker.chosenModel == nil)
    }
}
