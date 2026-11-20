/// A model to talk to, with the provider that serves it.
///
/// `provider` is a slug from `GET /api/model/options` (for example `anthropic`). It is `nil` for the
/// instance's own models (`hermes-agent` and the `/v1/models` aliases), where the instance picks the provider.
public struct ModelChoice: Hashable, Sendable {
    public var model: String
    public var provider: String?

    public init(model: String, provider: String? = nil) {
        self.model = model
        self.provider = provider
    }

    /// The gateway's virtual model: the instance answers with the model it is configured to use.
    public static let instanceDefault = ModelChoice(model: "hermes-agent")

    /// `provider · model`, or the model alone when there is no provider.
    public var displayName: String {
        Self.displayName(model: model, provider: provider)
    }

    public static func displayName(model: String, provider: String?) -> String {
        guard let provider, !provider.isEmpty else { return model }
        return "\(provider) · \(model)"
    }

    /// Trims both fields. A blank model gives `nil`; a blank provider becomes `nil`.
    public var normalized: ModelChoice? {
        let model = self.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        let provider = self.provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelChoice(model: model, provider: provider?.isEmpty == false ? provider : nil)
    }
}
