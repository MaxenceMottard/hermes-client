import Foundation
import HermesAPI
import Testing

@testable import HermesChat

/// Returns fixed listings, or throws the given error from the provider catalog.
struct FakeModelCatalog: ModelCatalog {
    var options: ModelOptionsResult = .fallback(.notFound)
    var models: ModelListResult = .fallback(.notFound)
    var error: (any Error)?

    func listModelOptions() async throws -> ModelOptionsResult {
        if let error {
            throw error
        }
        return options
    }

    func listModels() async throws -> ModelListResult {
        models
    }
}

@MainActor
@Suite("ModelPicker")
struct ModelPickerTests {
    private let instanceDefault = ModelChoice(model: "hermes-agent")
    private let catalogOptions = ModelOptions(providers: [
        ModelProviderOption(slug: "anthropic", name: "Anthropic", models: ["opus", "sonnet"]),
        ModelProviderOption(slug: "openai", name: "OpenAI", models: ["gpt"]),
    ])

    private func makePicker(_ catalog: FakeModelCatalog?, preferred: ModelChoice) -> ModelPicker {
        ModelPicker(catalog: catalog, preferred: preferred, defaultChoice: instanceDefault)
    }

    @Test("the provider catalog is shown as one section per provider, after the instance default")
    func providerSections() async {
        let picker = makePicker(FakeModelCatalog(options: .options(catalogOptions)), preferred: instanceDefault)
        #expect(picker.state == .loading)

        await picker.load()

        #expect(
            picker.state
                == .sections([
                    ModelSection(id: "default", title: "Instance default", choices: [instanceDefault]),
                    ModelSection(
                        id: "anthropic", title: "Anthropic",
                        choices: [
                            ModelChoice(model: "opus", provider: "anthropic"),
                            ModelChoice(model: "sonnet", provider: "anthropic"),
                        ]),
                    ModelSection(id: "openai", title: "OpenAI", choices: [ModelChoice(model: "gpt", provider: "openai")]),
                ]))
    }

    @Test("the preferred model stays selected when a provider lists it")
    func keepsListedPreferred() async {
        let preferred = ModelChoice(model: "sonnet", provider: "anthropic")
        let picker = makePicker(FakeModelCatalog(options: .options(catalogOptions)), preferred: preferred)

        await picker.load()

        #expect(picker.selection == preferred)
        #expect(picker.chosen == preferred)
    }

    @Test("the instance default is selected when the preferred model is not listed")
    func selectsDefaultWhenPreferredMissing() async {
        let picker = makePicker(
            FakeModelCatalog(options: .options(catalogOptions)),
            preferred: ModelChoice(model: "gone", provider: "anthropic"))

        await picker.load()

        #expect(picker.selection == instanceDefault)
    }

    @Test("the same model under another provider is not the preferred one")
    func providerIsPartOfTheChoice() async {
        let picker = makePicker(
            FakeModelCatalog(options: .options(catalogOptions)),
            preferred: ModelChoice(model: "gpt", provider: "anthropic"))

        await picker.load()

        #expect(picker.selection == instanceDefault)
    }

    @Test("without the provider catalog, the /v1/models list is shown without the default model twice")
    func fallsBackToInstanceModels() async {
        let picker = makePicker(
            FakeModelCatalog(options: .fallback(.notFound), models: .models(["hermes-agent", "fast"])),
            preferred: ModelChoice(model: "fast"))

        await picker.load()

        #expect(
            picker.state
                == .sections([
                    ModelSection(id: "default", title: "Instance default", choices: [instanceDefault]),
                    ModelSection(id: "instance", title: "Instance", choices: [ModelChoice(model: "fast")]),
                ]))
        #expect(picker.selection == ModelChoice(model: "fast"))
    }

    @Test("when both listings fail, the picker switches to manual entry with the preferred model filled in")
    func bothFailIsManual() async {
        let preferred = ModelChoice(model: "opus", provider: "anthropic")
        let picker = makePicker(
            FakeModelCatalog(options: .fallback(.notFound), models: .fallback(.unauthorized)), preferred: preferred)

        await picker.load()

        #expect(picker.state == .manual(.unauthorized))
        #expect(picker.selection == preferred)
    }

    @Test("without a catalog the picker starts in manual entry")
    func noCatalogIsManual() async {
        let picker = makePicker(nil, preferred: instanceDefault)
        #expect(picker.state == .manual(nil))

        await picker.load()

        #expect(picker.state == .manual(nil))
    }

    @Test("a cancelled load leaves the picker loading")
    func cancelledLoadKeepsState() async {
        let picker = makePicker(FakeModelCatalog(error: CancellationError()), preferred: instanceDefault)

        await picker.load()

        #expect(picker.state == .loading)
    }

    @Test("the chosen model is trimmed, a blank provider is dropped, and a blank model gives nil")
    func chosenNormalizes() {
        let picker = makePicker(nil, preferred: ModelChoice(model: "  m  ", provider: "  "))
        #expect(picker.chosen == ModelChoice(model: "m"))

        picker.selection = ModelChoice(model: " m ", provider: " anthropic ")
        #expect(picker.chosen == ModelChoice(model: "m", provider: "anthropic"))

        picker.selection.model = "   "
        #expect(picker.chosen == nil)
    }
}
