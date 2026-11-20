/// Outcome of `HermesClient.listModels()`. A failed listing is a value, not a blocking error:
/// the settings screen then accepts a model name typed by hand.
public enum ModelListResult: Sendable, Equatable {
    /// The model IDs (`data[].id`), in the order the instance returned them.
    case models([String])
    /// The list is unavailable. The reason is kept so the UI can explain it.
    case fallback(HermesAPIError)
}

/// Body of `GET /v1/models`. Only `data[].id` is read; unknown fields are ignored.
struct ModelList: Decodable, Sendable {
    var data: [Model]

    struct Model: Decodable, Sendable {
        var id: String
    }
}
