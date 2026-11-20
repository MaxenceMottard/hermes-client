import Foundation
import HermesAPI

#if !os(Linux)
    import Observation
#endif

/// The model listing a picker needs. `HermesClient` implements it; tests use a fake.
public protocol ModelCatalog: Sendable {
    func listModels() async throws -> ModelListResult
}

extension HermesClient: ModelCatalog {}

/// State of the screen shown before a new conversation: the models the instance lists, or a text field
/// when the list is unavailable. The preferred model (the last one used) is preselected.
///
/// `@Observable` is applied on Apple platforms, see `ChatSession` for why it is left out on Linux.
@MainActor
#if !os(Linux)
    @Observable
#endif
public final class ModelPicker {
    public enum State: Equatable, Sendable {
        /// The list is being fetched.
        case loading
        /// The models listed by the instance, in its order.
        case list([String])
        /// No list: the model name is typed by hand. Carries the reason when the listing failed.
        case manual(HermesAPIError?)
    }

    public private(set) var state: State
    /// The model the conversation will start on. Bound to the list selection or to the text field.
    public var selection: String

    private let catalog: (any ModelCatalog)?

    /// Without a catalog, the picker goes straight to manual entry.
    public init(catalog: (any ModelCatalog)?, preferred: String) {
        self.catalog = catalog
        selection = preferred
        state = catalog == nil ? .manual(nil) : .loading
    }

    /// Fetches the model list. Keeps the preferred model selected when the instance lists it,
    /// otherwise selects the first listed model. A failed listing switches to manual entry.
    /// A cancelled load leaves the state unchanged.
    public func load() async {
        guard let catalog else {
            state = .manual(nil)
            return
        }
        let result: ModelListResult
        do {
            result = try await catalog.listModels()
        } catch {
            return
        }
        switch result {
        case .models(let ids):
            state = .list(ids)
            if !ids.contains(selection), let first = ids.first {
                selection = first
            }
        case .fallback(let reason):
            state = .manual(reason)
        }
    }

    /// The trimmed selection, or `nil` when it is blank.
    public var chosenModel: String? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
