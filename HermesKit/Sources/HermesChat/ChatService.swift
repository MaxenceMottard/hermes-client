import HermesAPI

/// The chat operation a session needs. `HermesClient` implements it; tests use a fake.
public protocol ChatService: Sendable {
    /// `provider` is the provider slug of `model`, or `nil` to let the instance pick.
    func streamChat(model: String, provider: String?, messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error>
}

extension HermesClient: ChatService {}
