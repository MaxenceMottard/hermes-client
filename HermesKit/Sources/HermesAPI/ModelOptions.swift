/// A provider and the models it serves, as listed by `GET /api/model/options`.
public struct ModelProviderOption: Sendable, Equatable {
    /// Provider id sent as `provider` in a chat request (for example `anthropic`).
    public var slug: String
    /// Display name (for example `Anthropic`).
    public var name: String
    /// Model ids, in the instance's order, without the ones it marks unavailable.
    public var models: [String]
    /// `true` for the provider the instance uses by default.
    public var isCurrent: Bool

    public init(slug: String, name: String, models: [String], isCurrent: Bool = false) {
        self.slug = slug
        self.name = name
        self.models = models
        self.isCurrent = isCurrent
    }
}

/// The provider catalog of the instance, with its default model and provider.
public struct ModelOptions: Sendable, Equatable {
    public var providers: [ModelProviderOption]
    /// The instance's default model, if it says.
    public var currentModel: String?
    /// The instance's default provider slug, if it says.
    public var currentProvider: String?

    public init(providers: [ModelProviderOption], currentModel: String? = nil, currentProvider: String? = nil) {
        self.providers = providers
        self.currentModel = currentModel
        self.currentProvider = currentProvider
    }
}

/// Outcome of `HermesClient.listModelOptions()`. A failed listing is a value, so that the caller can fall
/// back to `/v1/models` or to a model name typed by hand.
public enum ModelOptionsResult: Sendable, Equatable {
    case options(ModelOptions)
    case fallback(HermesAPIError)
}

/// Body of `GET /api/model/options`. Only the fields the picker needs are read; unknown fields are ignored.
struct ModelOptionsPayload: Decodable, Sendable {
    var providers: [Row]
    var model: String?
    var provider: String?

    struct Row: Decodable, Sendable {
        var slug: String
        var name: String?
        var models: [String]?
        var isCurrent: Bool?
        var authenticated: Bool?
        var unavailableModels: [String]?

        enum CodingKeys: String, CodingKey {
            case slug, name, models, authenticated
            case isCurrent = "is_current"
            case unavailableModels = "unavailable_models"
        }
    }

    /// Keeps the providers that can be used: signed in (`authenticated` is not `false`) and with at least
    /// one available model.
    var options: ModelOptions {
        let providers = self.providers.compactMap { row -> ModelProviderOption? in
            guard row.authenticated != false, !row.slug.isEmpty else { return nil }
            let unavailable = Set(row.unavailableModels ?? [])
            let models = (row.models ?? []).filter { !$0.isEmpty && !unavailable.contains($0) }
            guard !models.isEmpty else { return nil }
            let name = row.name.flatMap { $0.isEmpty ? nil : $0 } ?? row.slug
            return ModelProviderOption(slug: row.slug, name: name, models: models, isCurrent: row.isCurrent ?? false)
        }
        return ModelOptions(providers: providers, currentModel: model, currentProvider: provider)
    }
}
