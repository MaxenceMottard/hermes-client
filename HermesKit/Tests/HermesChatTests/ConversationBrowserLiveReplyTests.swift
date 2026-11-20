import Foundation
import HermesAPI
import HermesStore
import Testing

@testable import HermesChat

/// Streams one delta for each message, then stays open until the consumer cancels.
actor HangingChatStreamSource: SessionListing {
    private(set) var listedFor: [String] = []

    func forkSession(sessionID: String) async throws -> RemoteSession {
        throw HermesAPIError.notFound
    }

    func listSessions(limit: Int, offset: Int) async throws -> SessionPage {
        SessionPage(sessions: [], hasMore: false)
    }

    func listSessionMessages(sessionID: String, limit: Int, offset: Int) async throws -> SessionMessagesPage {
        listedFor.append(sessionID)
        return SessionMessagesPage(sessionID: sessionID, messages: [], hasMore: false)
    }

    func streamSessionChat(
        sessionID: String, message: String, images: [ImageAttachment]
    ) -> AsyncThrowingStream<SessionChatEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.delta("Hel"))
                try? await Task.sleep(for: .seconds(30))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Waits until `condition` holds, for up to 2 seconds.
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
@Suite("ConversationBrowser live replies")
struct ConversationBrowserLiveReplyTests {
    @Test("a local conversation left while its reply streams opens again on the same session")
    func reopenStreamingLocal() async throws {
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: [.hang(["Hel"])]),
            model: "m"
        )
        let id = try #require(browser.selectedID)
        let session = try #require(browser.session)
        let send = Task { await session.send("Hi") }
        await waitUntil { session.messages.last?.content == "Hel" }

        browser.selectEntry(nil)
        browser.select(id)

        #expect(browser.session === session)
        #expect(browser.session?.isBusy == true)
        session.stop()
        await send.value
    }

    @Test("a local conversation left while its reply streams keeps its session across another conversation")
    func reopenStreamingLocalAfterAnother() async throws {
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: [.hang(["Hel"])]),
            model: "m"
        )
        let id = try #require(browser.selectedID)
        let session = try #require(browser.session)
        let send = Task { await session.send("Hi") }
        await waitUntil { session.messages.last?.content == "Hel" }

        _ = try browser.createConversation()
        browser.select(id)

        #expect(browser.session === session)
        session.stop()
        await send.value
    }

    @Test("a local conversation whose reply ended opens on a session read from the store")
    func reopenFinishedLocal() async throws {
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: [.deltas(["Hello"])]),
            model: "m"
        )
        let id = try #require(browser.selectedID)
        let session = try #require(browser.session)
        await session.send("Hi")

        browser.selectEntry(nil)
        browser.select(id)

        #expect(browser.session !== session)
        #expect(browser.session?.messages.map(\.content) == ["Hi", "Hello"])
    }

    @Test("deleting a conversation left while its reply streams stops the reply")
    func deleteStopsKeptReply() async throws {
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: [.hang(["Hel"])]),
            model: "m"
        )
        let id = try #require(browser.selectedID)
        let session = try #require(browser.session)
        let send = Task { await session.send("Hi") }
        await waitUntil { session.messages.last?.content == "Hel" }
        _ = try browser.createConversation()

        try browser.delete(id)
        await send.value

        #expect(!session.isBusy)
    }

    @Test("a remote session left while its reply streams opens again on the same transcript, not reloaded")
    func reopenStreamingRemote() async throws {
        let source = HangingChatStreamSource()
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: []),
            model: "m",
            remoteSessions: RemoteSessionList(source: source)
        )
        let remote = RemoteSession(id: "api-1", source: "api_server")
        browser.openRemote(remote)
        let transcript = try #require(browser.openedRemote)
        await transcript.load()
        let send = Task { await transcript.send("Hi") }
        await waitUntil { transcript.lines.last?.text == "Hel" }

        browser.selectEntry(nil)
        browser.openRemote(remote)

        #expect(browser.openedRemote === transcript)
        #expect(transcript.isSending)
        #expect(transcript.lines.map(\.text) == ["Hi", "Hel"])
        #expect(await source.listedFor == ["api-1"])
        transcript.stop()
        await send.value
    }

    @Test("a remote session whose reply ended opens on a new transcript")
    func reopenFinishedRemote() async throws {
        let source = FakeChatStreamSource(events: [.completed("Hello")])
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(),
            service: FakeChatService(scripts: []),
            model: "m",
            remoteSessions: RemoteSessionList(source: source)
        )
        let remote = RemoteSession(id: "api-1", source: "api_server")
        browser.openRemote(remote)
        let transcript = try #require(browser.openedRemote)
        await transcript.send("Hi")

        browser.selectEntry(nil)
        browser.openRemote(remote)

        #expect(browser.openedRemote !== transcript)
    }
}
