import Foundation
import HermesAPI
import Testing

@testable import HermesChat

/// Scripted fake: returns queued results and records every history it was called with.
actor FakeChatService: ChatService {
    private var results: [Result<String, any Error>]
    private(set) var requests: [[ChatMessage]] = []

    init(results: [Result<String, any Error>]) {
        self.results = results
    }

    func chat(model: String, messages: [ChatMessage]) async throws -> String {
        requests.append(messages)
        guard !results.isEmpty else { throw HermesAPIError.invalidResponse }
        return try results.removeFirst().get()
    }
}

@MainActor
@Suite("ChatSession history")
struct ChatSessionTests {
    @Test("a send appends the user message and the assistant reply")
    func sendAppendsBothMessages() async {
        let service = FakeChatService(results: [.success("Hello")])
        let session = ChatSession(service: service, model: "m")

        await session.send("  Hi  ")

        #expect(
            session.messages == [
                ChatMessage(role: "user", content: "Hi"),
                ChatMessage(role: "assistant", content: "Hello"),
            ])
        #expect(session.phase == .idle)
    }

    @Test("each send transmits the full history, not only the last message")
    func historyIsSentEachTime() async {
        let service = FakeChatService(results: [.success("A1"), .success("A2")])
        let session = ChatSession(service: service, model: "m")

        await session.send("Q1")
        await session.send("Q2")

        let requests = await service.requests
        #expect(requests.count == 2)
        #expect(
            requests[1] == [
                ChatMessage(role: "user", content: "Q1"),
                ChatMessage(role: "assistant", content: "A1"),
                ChatMessage(role: "user", content: "Q2"),
            ])
    }

    @Test("blank input is ignored and sends nothing")
    func blankInputIgnored() async {
        let service = FakeChatService(results: [])
        let session = ChatSession(service: service, model: "m")

        await session.send("   \n ")

        #expect(session.messages.isEmpty)
        #expect(await service.requests.isEmpty)
    }

    @Test("a failed request sets the failed phase with a typed error")
    func failureSetsPhase() async {
        let service = FakeChatService(results: [.failure(URLError(.notConnectedToInternet))])
        let session = ChatSession(service: service, model: "m")

        await session.send("Hi")

        #expect(session.phase == .failed(.network))
        #expect(session.messages == [ChatMessage(role: "user", content: "Hi")])
    }
}
