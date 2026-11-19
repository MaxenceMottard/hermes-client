import HermesAPI

#if !os(Linux)
    import Observation
#endif

/// A conversation with the agent: keeps the history and sends the full history with each message.
///
/// `@Observable` is applied on Apple platforms (the app targets). It is left out on Linux, where the
/// toolchain's `Observation` library fails to link; the logic under test is identical.
@MainActor
#if !os(Linux)
    @Observable
#endif
public final class ChatSession {
    public enum Phase: Equatable, Sendable {
        case idle
        case sending
        case failed(HermesAPIError)
    }

    public private(set) var messages: [ChatMessage] = []
    public private(set) var phase: Phase = .idle

    private let service: any ChatService
    private let model: String

    public init(service: any ChatService, model: String) {
        self.service = service
        self.model = model
    }

    /// Appends the user message, sends the whole history, and appends the assistant reply.
    /// Blank input and sends issued while a reply is pending are ignored.
    public func send(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, phase != .sending else { return }
        messages.append(ChatMessage(role: "user", content: content))
        await requestReply()
    }

    private func requestReply() async {
        phase = .sending
        do {
            let reply = try await service.chat(model: model, messages: messages)
            messages.append(ChatMessage(role: "assistant", content: reply))
            phase = .idle
        } catch {
            phase = .failed(HermesAPIError.from(error))
        }
    }
}
