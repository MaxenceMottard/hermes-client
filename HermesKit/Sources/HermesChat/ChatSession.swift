import HermesAPI

#if !os(Linux)
    import Observation
#endif

/// A conversation with the agent: keeps the history, sends it with each message, and streams replies.
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
        /// Request sent, no text received yet.
        case sending
        /// Text is arriving.
        case streaming
        case failed(HermesAPIError)
    }

    public private(set) var messages: [ChatMessage] = []
    public private(set) var phase: Phase = .idle

    private let service: any ChatService
    private let model: String
    private var sendTask: Task<Void, Never>?

    public init(service: any ChatService, model: String) {
        self.service = service
        self.model = model
    }

    /// `true` while a reply is pending or streaming.
    public var isBusy: Bool {
        phase == .sending || phase == .streaming
    }

    /// Appends the user message, then streams the reply into a new assistant message.
    /// Blank input and sends issued while a reply is pending are ignored.
    public func send(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isBusy else { return }
        messages.append(ChatMessage(role: "user", content: content))

        let task = Task { await self.requestReply() }
        sendTask = task
        await task.value
        sendTask = nil
    }

    /// Stops the reply in progress. The partial text is kept; an empty placeholder is removed.
    public func stop() {
        sendTask?.cancel()
    }

    private func requestReply() async {
        phase = .sending
        messages.append(ChatMessage(role: "assistant", content: ""))
        let index = messages.count - 1
        let history = Array(messages.dropLast())

        do {
            for try await delta in service.streamChat(model: model, messages: history) {
                messages[index].content += delta
                phase = .streaming
            }
            if Task.isCancelled {
                discardIfEmpty(index)
                phase = .idle
            } else {
                phase = .idle
            }
        } catch {
            discardIfEmpty(index)
            phase = .failed(HermesAPIError.from(error))
        }
    }

    private func discardIfEmpty(_ index: Int) {
        if messages.indices.contains(index), messages[index].content.isEmpty {
            messages.remove(at: index)
        }
    }
}
