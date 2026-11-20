/// Paths of the Hermes API. Conversations go through the session endpoints (`/api/sessions`), so that
/// every conversation is one session stored on the instance.
public enum HermesAPIPaths {
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

    /// One session, `GET`, `PATCH` (title) or `DELETE /api/sessions/{id}`. The id is appended as a path segment.
    /// Read from the Hermes gateway source (`api_server.py`).
    public static func session(_ sessionID: String) -> String {
        "\(sessions)/\(sessionID)"
    }

    /// Messages of one session, `GET /api/sessions/{id}/messages`. The id is appended as a path segment.
    public static func sessionMessages(_ sessionID: String) -> String {
        "\(sessions)/\(sessionID)/messages"
    }

    /// Fork of one session, `POST /api/sessions/{id}/fork`. Copies the messages into a new API session
    /// and ends the original. Read from the Hermes gateway source (`api_server.py`).
    public static func sessionFork(_ sessionID: String) -> String {
        "\(sessions)/\(sessionID)/fork"
    }

    /// Chat stream of one session, `POST /api/sessions/{id}/chat/stream` (server-sent events).
    public static func sessionChatStream(_ sessionID: String) -> String {
        "\(sessions)/\(sessionID)/chat/stream"
    }

    /// Provider model catalog, the one the dashboard's model picker shows (models grouped by provider).
    /// `/v1/models` only lists the virtual `hermes-agent` model and the configured aliases.
    /// needs-verification: read from the Hermes gateway source (`GET /api/model/options`, Bearer auth);
    /// not checked on the real instance yet.
    public static let modelOptions = "/api/model/options"
}
