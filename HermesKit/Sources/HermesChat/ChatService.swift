import HermesAPI

/// The chat operations a session needs. `HermesClient` implements it; tests use a fake.
public protocol ChatService: Sendable {
    func chat(model: String, messages: [ChatMessage]) async throws -> String
}

extension HermesClient: ChatService {}
