import Foundation
import HermesAPI
import Testing

@testable import HermesChat

/// Scripted fake. Each `streamChat` call consumes one script and records the history it received.
final class FakeChatService: ChatService, @unchecked Sendable {
    enum Script: Sendable {
        /// Yields these deltas, then finishes.
        case deltas([String])
        /// Fails with this error.
        case fail(URLError)
        /// Yields these deltas, then stays open until the consumer cancels.
        case hang([String])
    }

    private let lock = NSLock()
    private var scripts: [Script]
    private var requests: [[ChatMessage]] = []
    private var models: [String] = []

    init(scripts: [Script]) {
        self.scripts = scripts
    }

    func recordedRequests() -> [[ChatMessage]] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    /// The model of each request, in order.
    func recordedModels() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return models
    }

    func streamChat(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error> {
        lock.lock()
        requests.append(messages)
        models.append(model)
        let script = scripts.isEmpty ? Script.deltas([]) : scripts.removeFirst()
        lock.unlock()

        return AsyncThrowingStream { continuation in
            let task = Task {
                switch script {
                case .deltas(let deltas):
                    for delta in deltas {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                case .fail(let error):
                    continuation.finish(throwing: error)
                case .hang(let deltas):
                    for delta in deltas {
                        continuation.yield(delta)
                    }
                    try? await Task.sleep(for: .seconds(30))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
@Suite("ChatSession")
struct ChatSessionTests {
    @Test("a send streams the reply into an assistant message and ends idle")
    func streamsReply() async {
        let service = FakeChatService(scripts: [.deltas(["Hel", "lo"])])
        let session = ChatSession(service: service, model: "m")

        await session.send("  Hi  ")

        #expect(
            session.messages == [
                ChatMessage(role: "user", content: "Hi"),
                ChatMessage(role: "assistant", content: "Hello"),
            ])
        #expect(session.phase == .idle)
        #expect(!session.isBusy)
    }

    @Test("each send transmits the full history, including earlier replies")
    func historyIsSentEachTime() async {
        let service = FakeChatService(scripts: [.deltas(["A1"]), .deltas(["A2"])])
        let session = ChatSession(service: service, model: "m")

        await session.send("Q1")
        await session.send("Q2")

        let requests = service.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests[0] == [ChatMessage(role: "user", content: "Q1")])
        #expect(
            requests[1] == [
                ChatMessage(role: "user", content: "Q1"),
                ChatMessage(role: "assistant", content: "A1"),
                ChatMessage(role: "user", content: "Q2"),
            ])
    }

    @Test("blank input is ignored and sends nothing")
    func blankInputIgnored() async {
        let service = FakeChatService(scripts: [])
        let session = ChatSession(service: service, model: "m")

        await session.send("   \n ")

        #expect(session.messages.isEmpty)
        #expect(service.recordedRequests().isEmpty)
    }

    @Test("a failure before any text removes the placeholder and sets the failed phase")
    func failureSetsPhase() async {
        let service = FakeChatService(scripts: [.fail(URLError(.notConnectedToInternet))])
        let session = ChatSession(service: service, model: "m")

        await session.send("Hi")

        #expect(session.phase == .failed(.network))
        #expect(session.messages == [ChatMessage(role: "user", content: "Hi")])
    }

    @Test("stop keeps the partial reply and returns to idle")
    func stopKeepsPartialReply() async {
        let service = FakeChatService(scripts: [.hang(["Hel"])])
        let session = ChatSession(service: service, model: "m")

        let send = Task { await session.send("Hi") }
        for _ in 0..<200 where session.messages.last?.content != "Hel" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.phase == .streaming)

        session.stop()
        await send.value

        #expect(session.phase == .idle)
        #expect(session.messages.last == ChatMessage(role: "assistant", content: "Hel"))
    }

    @Test("an empty reply sets emptyReply, leaves no placeholder, and can be retried")
    func emptyReplyCanBeRetried() async {
        let service = FakeChatService(scripts: [.deltas([]), .deltas(["Done"])])
        let session = ChatSession(service: service, model: "m")

        await session.send("Hi")
        #expect(session.phase == .emptyReply)
        #expect(session.canRetry)
        #expect(session.messages == [ChatMessage(role: "user", content: "Hi")])

        await session.retry()

        #expect(session.phase == .idle)
        #expect(
            session.messages == [
                ChatMessage(role: "user", content: "Hi"),
                ChatMessage(role: "assistant", content: "Done"),
            ])
    }

    @Test("retry resends the same history without duplicating the user message")
    func retryResendsSameHistory() async {
        let service = FakeChatService(scripts: [.fail(URLError(.timedOut)), .deltas(["Ok"])])
        let session = ChatSession(service: service, model: "m")

        await session.send("Hi")
        #expect(session.phase == .failed(.timeout))

        await session.retry()

        let requests = service.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests[0] == requests[1])
        #expect(requests[1] == [ChatMessage(role: "user", content: "Hi")])
        #expect(session.phase == .idle)
    }

    @Test("retry is ignored when there is nothing to retry")
    func retryIgnoredWhenNotFailed() async {
        let service = FakeChatService(scripts: [.deltas(["Hello"])])
        let session = ChatSession(service: service, model: "m")

        await session.send("Hi")
        #expect(!session.canRetry)

        await session.retry()

        #expect(service.recordedRequests().count == 1)
    }
}
