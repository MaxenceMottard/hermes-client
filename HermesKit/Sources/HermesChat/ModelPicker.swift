import Foundation
import HermesAPI

#if !os(Linux)
    import Observation
#endif

/// The model listings a picker needs. `HermesClient` implements them; tests use a fake.
public protocol ModelCatalog: Sendable {
    /// The provider catalog (`GET /api/model/options`): models grouped by provider.
    func listModelOptions() async throws -> ModelOptionsResult
    /// The instance's own models (`GET /v1/models`): `hermes-agent` and the configured aliases.
    func listModels() async throws -> ModelListResult
}

extension HermesClient: ModelCatalog {}

/// A titled group of models in the picker: one provider, the instance default, or the `/v1/models` list.
public struct ModelSection: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var choices: [ModelChoice]

    public init(id: String, title: String, choices: [ModelChoice]) {
        self.id = id
        self.title = title
        self.choices = choices
    }
}

/// State of the screen shown before a new conversation: the models grouped by provider, as the dashboard
/// shows them, or text fields when no list is available. The preferred model (the last one used) is
/// preselected.
///
/// `@Observable` is applied on Apple platforms, see `ChatSession` for why it is left out on Linux.
@MainActor
#if !os(Linux)
    @Observable
#endif
public final class ModelPicker {
    public enum State: Equatable, Sendable {
        /// The lists are being fetched.
        case loading
        /// The sections to pick from. The first one holds the instance default.
        case sections([ModelSection])
        /// No list: the model (and optionally its provider) is typed by hand. Carries the reason when the
        /// listing failed.
        case manual(HermesAPIError?)
    }

    static let defaultSectionID = "default"
    static let instanceSectionID = "instance"

    public private(set) var state: State
    /// The model the conversation will start on. Bound to the list selection or to the text fields.
    public var selection: ModelChoice
    /// Ids of the sections that show their models. When the lists load, only the section holding the
    /// selection is open.
    public private(set) var expandedSectionIDs: Set<String> = []

    private let catalog: (any ModelCatalog)?
    private let defaultChoice: ModelChoice

    /// `defaultChoice` is the instance default (the model from the settings, no provider). It is always
    /// offered, and selected when `preferred` is not in the lists. Without a catalog, the picker goes
    /// straight to manual entry.
    public init(catalog: (any ModelCatalog)?, preferred: ModelChoice, defaultChoice: ModelChoice) {
        self.catalog = catalog
        self.defaultChoice = defaultChoice
        selection = preferred
        state = catalog == nil ? .manual(nil) : .loading
    }

    /// Fetches the provider catalog. If it is unavailable, falls back to `/v1/models`, then to manual
    /// entry. Keeps the preferred model selected when it is listed, otherwise selects the instance default.
    /// A cancelled load leaves the state unchanged.
    public func load() async {
        guard let catalog else {
            state = .manual(nil)
            return
        }
        do {
            switch try await catalog.listModelOptions() {
            case .options(let options):
                show(
                    options.providers.map { provider in
                        ModelSection(
                            id: provider.slug,
                            title: provider.name,
                            choices: provider.models.map { ModelChoice(model: $0, provider: provider.slug) }
                        )
                    })
            case .fallback:
                switch try await catalog.listModels() {
                case .models(let ids):
                    let choices = ids.map { ModelChoice(model: $0) }.filter { $0 != defaultChoice }
                    show(
                        choices.isEmpty
                            ? [] : [ModelSection(id: Self.instanceSectionID, title: "Instance", choices: choices)])
                case .fallback(let reason):
                    state = .manual(reason)
                }
            }
        } catch {
            return
        }
    }

    /// The trimmed selection, or `nil` when the model is blank.
    public var chosen: ModelChoice? {
        selection.normalized
    }

    /// Whether the section with this id shows its models.
    public func isExpanded(_ sectionID: String) -> Bool {
        expandedSectionIDs.contains(sectionID)
    }

    /// Opens a closed section, or closes an open one. Does not change the selection.
    public func toggle(_ sectionID: String) {
        if expandedSectionIDs.contains(sectionID) {
            expandedSectionIDs.remove(sectionID)
        } else {
            expandedSectionIDs.insert(sectionID)
        }
    }

    /// Shows the sections, keeps the selection if listed (else selects the default), and opens only the
    /// section that holds the selection.
    private func show(_ sections: [ModelSection]) {
        let defaultSection = ModelSection(id: Self.defaultSectionID, title: "Instance default", choices: [defaultChoice])
        let all = [defaultSection] + sections
        state = .sections(all)
        if !all.contains(where: { $0.choices.contains(selection) }) {
            selection = defaultChoice
        }
        expandedSectionIDs = Set(all.first { $0.choices.contains(selection) }.map { [$0.id] } ?? [])
    }
}
