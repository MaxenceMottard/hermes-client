/// Hermes API (OpenAI-compatible) constants. `chatCompletions` is confirmed by the contract.
/// The other paths are `needs-verification` (see the health check and model list issues).
public enum HermesAPIPaths {
    public static let chatCompletions = "/v1/chat/completions"

    /// Health probe used by "Test connection".
    /// needs-verification: the Hermes gateway source registers `GET /health` and answers without
    /// checking the API key. The real instance has not been checked yet.
    public static let health = "/health"
}
