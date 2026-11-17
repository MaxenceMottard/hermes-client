import HermesAPI

/// The chat operation a session needs. `HermesClient` implements it; tests use a fake.
public protocol ChatService: Sendable {
    func streamChat(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error>
}

extension HermesClient: ChatService {}
