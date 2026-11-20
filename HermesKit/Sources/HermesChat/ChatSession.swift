import Foundation
import HermesAPI
import HermesStore

#if !os(Linux)
    import Observation
#endif

/// A conversation with the agent: keeps the history, sends it with each message, streams replies,
/// and saves the conversation to a `ConversationStore` when one is given.
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
        /// The request failed. The user message is kept so the reply can be retried.
        case failed(HermesAPIError)
        /// The agent finished without any text. The user message is kept so the reply can be retried.
        case emptyReply
    }

    /// Number of streamed deltas between two saves while a reply is arriving.
    static let saveInterval = 20

    /// Maximum number of images sent with one message.
    public static let maxImagesPerMessage = 4

    public private(set) var messages: [ChatMessage] = []
    public private(set) var phase: Phase = .idle
    /// The model every request of this session is sent to.
    public let model: String
    /// The provider of `model`, sent with every request. `nil` lets the instance pick.
    public let provider: String?

    /// `model` and `provider` together.
    public var modelChoice: ModelChoice {
        ModelChoice(model: model, provider: provider)
    }

    private let service: any ChatService
    private let store: (any ConversationStore)?
    private let conversationID: UUID?
    private var sendTask: Task<Void, Never>?

    /// Without a store, the session lives in memory only. With a store and a conversation id, it loads the
    /// saved messages and saves to that conversation. A model saved with the conversation takes precedence
    /// over `model` and `provider`, which are then only the fallback for conversations saved without one.
    public init(
        service: any ChatService,
        model: String,
        provider: String? = nil,
        store: (any ConversationStore)? = nil,
        conversationID: UUID? = nil
    ) {
        self.service = service
        self.store = store
        self.conversationID = conversationID
        let saved = conversationID.flatMap { id in try? store?.conversation(id: id) }
        if let savedModel = saved?.model {
            self.model = savedModel
            self.provider = saved?.provider
        } else {
            self.model = model
            self.provider = provider
        }
        if let saved {
            messages = saved.messages.map { ChatMessage(role: $0.role, content: $0.content) }
        }
    }

    /// `true` while a reply is pending or streaming.
    public var isBusy: Bool {
        phase == .sending || phase == .streaming
    }

    /// `true` when the last reply failed or came back empty and the user message can be sent again.
    public var canRetry: Bool {
        switch phase {
        case .failed, .emptyReply:
            messages.last?.role == "user"
        default:
            false
        }
    }

    /// Appends the user message, then streams the reply into a new assistant message.
    /// A message needs text, images, or both. Empty input, more than `maxImagesPerMessage` images, and sends
    /// issued while a reply is pending are ignored.
    ///
    /// Images are kept in memory for the session. They are not saved with the conversation, so after a
    /// reload the earlier messages are sent to the instance as text only.
    public func send(_ text: String, images: [ImageAttachment] = []) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(content.isEmpty && images.isEmpty), !isBusy else { return }
        guard images.count <= Self.maxImagesPerMessage else { return }
        messages.append(ChatMessage(role: "user", content: content, images: images))
        titleIfUntitled(from: content.isEmpty ? "Image" : content)
        persist()
        await runReply()
    }

    /// Sends the last user message again after a failed or empty reply.
    public func retry() async {
        guard canRetry, !isBusy else { return }
        await runReply()
    }

    /// Stops the reply in progress. The partial text is kept; an empty placeholder is removed.
    public func stop() {
        sendTask?.cancel()
    }

    private func runReply() async {
        let task = Task { await self.requestReply() }
        sendTask = task
        await task.value
        sendTask = nil
    }

    private func requestReply() async {
        phase = .sending
        messages.append(ChatMessage(role: "assistant", content: ""))
        let index = messages.count - 1
        let history = Array(messages.dropLast())
        var deltaCount = 0
        defer { persist() }

        do {
            for try await delta in service.streamChat(model: model, provider: provider, messages: history) {
                messages[index].content += delta
                phase = .streaming
                deltaCount += 1
                if deltaCount % Self.saveInterval == 0 {
                    persist()
                }
            }
            if Task.isCancelled {
                discardIfEmpty(index)
                phase = .idle
            } else if messages[index].content.isEmpty {
                discardIfEmpty(index)
                phase = .emptyReply
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

    /// Gives the conversation a title from its first message, unless the user already named it.
    private func titleIfUntitled(from content: String) {
        guard let store, let conversationID,
            messages.filter({ $0.role == "user" }).count == 1,
            let saved = try? store.conversation(id: conversationID),
            saved.title == ConversationTitle.placeholder
        else { return }
        try? store.rename(conversation: conversationID, to: ConversationTitle.derive(from: content))
    }

    /// Saves the messages to the store. Empty assistant placeholders are not saved.
    /// Save failures are not shown: the in-memory conversation stays usable.
    private func persist() {
        guard let store, let conversationID else { return }
        let stored =
            messages
            .filter { !($0.role == "assistant" && $0.content.isEmpty) }
            .map { StoredMessage(role: $0.role, content: $0.content) }
        try? store.replaceMessages(stored, inConversation: conversationID)
    }
}
