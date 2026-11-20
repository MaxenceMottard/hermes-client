/// Hermes API (OpenAI-compatible) constants. `chatCompletions` is confirmed by the contract.
/// The other paths are `needs-verification` (see the health check and model list issues).
public enum HermesAPIPaths {
    public static let chatCompletions = "/v1/chat/completions"

    /// Health probe used by "Test connection".
    /// needs-verification: the Hermes gateway source registers `GET /health` and answers without
    /// checking the API key. The real instance has not been checked yet.
    public static let health = "/health"

    /// Model list used by the settings screen, with a manual fallback.
    /// needs-verification: the Hermes gateway source registers `GET /v1/models` with the same Bearer auth.
    /// The real instance has not been checked yet.
    public static let models = "/v1/models"

    /// Session list used by the conversation list, `GET /api/sessions?limit&offset`.
    /// Read from the Hermes gateway source (`api_server.py`); the real instance has not been checked yet.
    public static let sessions = "/api/sessions"

    /// Messages of one session, `GET /api/sessions/{id}/messages`. The id is appended as a path segment.
    public static func sessionMessages(_ sessionID: String) -> String {
        "\(sessions)/\(sessionID)/messages"
    }
}
