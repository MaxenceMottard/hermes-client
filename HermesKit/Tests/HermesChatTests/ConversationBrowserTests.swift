import Foundation
import HermesAPI
import HermesStore
import Testing

@testable import HermesChat

/// Waits until `condition` holds, for work the browser starts in its own tasks. Gives up after a second.
@MainActor
func waitUntil(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
@Suite("ConversationBrowser")
struct ConversationBrowserTests {
    private func makeBrowser(
        instance: FakeInstance = FakeInstance(),
        store: InMemoryConversationStore = InMemoryConversationStore(),
        lastModel: InMemoryLastModelStorage? = nil
    ) -> ConversationBrowser {
        ConversationBrowser(
            store: store,
            remoteSessions: RemoteSessionList(source: instance),
            model: "default-model",
            lastModel: lastModel
        )
    }

    // MARK: Start

    @Test("nothing is created or opened on start, and conversations saved on this device are listed")
    func startsClosed() throws {
        let store = InMemoryConversationStore()
        _ = try store.createConversation(title: "Old chat")

        let browser = makeBrowser(store: store)

        #expect(browser.summaries.map(\.title) == ["Old chat"])
        #expect(browser.openedRemote == nil)
        #expect(browser.archived == nil)
        #expect(browser.selectedEntryID == nil)
        #expect(try store.summaries().count == 1)
    }

    // MARK: New conversation

    @Test("a new conversation is a session created on the instance with its model locked, opened empty")
    func createLocksModel() async throws {
        let instance = FakeInstance()
        let storage = InMemoryLastModelStorage()
        let browser = makeBrowser(instance: instance, lastModel: storage)

        let session = try await browser.createConversation(model: " opus ", provider: "anthropic")

        #expect(await instance.created == [FakeInstance.Created(model: "opus", provider: "anthropic")])
        #expect(browser.openedRemote?.sessionID == session.id)
        #expect(browser.openedRemote?.model == ModelChoice(model: "opus", provider: "anthropic"))
        #expect(browser.openedRemote?.state == .loaded)
        #expect(browser.remoteSessions.sessions.first?.id == session.id)
        #expect(browser.selectedEntryID == SidebarEntry.remoteID(session.id))
        #expect(storage.load() == ModelChoice(model: "opus", provider: "anthropic"))
        #expect(!browser.isCreating)
        // Nothing to load: the session was just created.
        #expect(await instance.messageRequests.isEmpty)
    }

    @Test("the instance default model is not sent: the instance picks its configured model")
    func createWithInstanceDefault() async throws {
        let instance = FakeInstance()
        let browser = makeBrowser(instance: instance)

        try await browser.createConversation(model: "hermes-agent")

        #expect(await instance.created == [FakeInstance.Created(model: nil, provider: nil)])
        #expect(browser.openedRemote?.model == ModelChoice.instanceDefault)
    }

    @Test("without a choice, a new conversation runs on the last used model and saves nothing")
    func createWithoutChoiceUsesLastModel() async throws {
        let instance = FakeInstance()
        let storage = InMemoryLastModelStorage(choice: ModelChoice(model: "saved", provider: "openai"))
        let browser = makeBrowser(instance: instance, lastModel: storage)

        try await browser.createConversation()

        #expect(await instance.created == [FakeInstance.Created(model: "saved", provider: "openai")])
        #expect(storage.load() == ModelChoice(model: "saved", provider: "openai"))
    }

    @Test("with nothing saved, new conversations start on the default model")
    func defaultWhenNothingSaved() {
        let browser = makeBrowser(lastModel: InMemoryLastModelStorage())

        #expect(browser.preferredChoice == ModelChoice(model: "default-model"))
        #expect(browser.defaultChoice == ModelChoice(model: "default-model"))
    }

    @Test("a new conversation left before any message is deleted from the instance and the list")
    func abandonedNewConversationIsDeleted() async throws {
        let instance = FakeInstance()
        let browser = makeBrowser(instance: instance)
        let session = try await browser.createConversation(model: "opus")

        browser.selectEntry(nil)

        await waitUntil { await instance.deleted == [session.id] }
        #expect(await instance.deleted == [session.id])
        #expect(browser.openedRemote == nil)
        await waitUntil { browser.remoteSessions.sessions.isEmpty }
        #expect(browser.remoteSessions.sessions.isEmpty)
    }

    @Test("a second new conversation replaces an untouched first one")
    func secondNewConversationReplacesUntouched() async throws {
        let instance = FakeInstance()
        let browser = makeBrowser(instance: instance)
        let first = try await browser.createConversation(model: "opus")

        let second = try await browser.createConversation(model: "opus")

        await waitUntil { await instance.deleted == [first.id] }
        #expect(await instance.deleted == [first.id])
        #expect(browser.openedRemote?.sessionID == second.id)
    }

    @Test("a new conversation with a message is kept when left, and gets the title the instance gives it")
    func usedNewConversationIsKept() async throws {
        let instance = FakeInstance(titleAfterReply: "Trip plans")
        let browser = makeBrowser(instance: instance)
        let session = try await browser.createConversation(model: "opus")
        let transcript = try #require(browser.openedRemote)

        await transcript.send("Plan a trip")
        await waitUntil { transcript.title == "Trip plans" }

        #expect(transcript.title == "Trip plans")
        #expect(browser.remoteSessions.sessions.first?.title == "Trip plans")
        browser.selectEntry(nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(await instance.deleted.isEmpty)
        #expect(browser.remoteSessions.sessions.map(\.id) == [session.id])
    }

    // MARK: Selection

    @Test("opening a session starts loading its messages without the view")
    func openRemoteStartsLoading() async throws {
        let source = GatedMessageSource(page: SessionMessagesPage(
            sessionID: "remote-1",
            messages: [SessionMessage(id: "1", role: "user", content: "Hi")],
            hasMore: false
        ))
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(), remoteSessions: RemoteSessionList(source: source))

        browser.openRemote(RemoteSession(id: "remote-1"))
        await waitUntil { await source.pendingCount == 1 }
        await source.release()
        let transcript = try #require(browser.openedRemote)
        await waitUntil { transcript.state == .loaded }

        #expect(transcript.lines.map(\.text) == ["Hi"])
        #expect(await source.requestCount == 1)
    }

    @Test("a row id opens its conversation: a session, or a read-only one saved on this device")
    func selectEntryOpensRows() async throws {
        let instance = FakeInstance(sessions: [RemoteSession(id: "remote-1", title: "Notes")])
        let store = InMemoryConversationStore()
        let local = try store.createConversation(title: "Old chat")
        try store.replaceMessages([StoredMessage(role: "user", content: "Hi")], inConversation: local.id)
        let browser = makeBrowser(instance: instance, store: store)
        await browser.reloadSessions()

        browser.selectEntry(SidebarEntry.remoteID("remote-1"))
        #expect(browser.openedRemote?.title == "Notes")
        #expect(browser.archived == nil)

        browser.selectEntry(SidebarEntry.localID(local.id))
        #expect(browser.openedRemote == nil)
        #expect(browser.archived?.messages.map(\.content) == ["Hi"])
        #expect(browser.selectedEntryID == SidebarEntry.localID(local.id))

        browser.selectEntry(nil)
        #expect(browser.archived == nil)
        #expect(browser.selectedEntryID == nil)
    }

    @Test("selecting the open session again keeps its transcript; an unknown row changes nothing")
    func reselectKeepsTranscript() async {
        let instance = FakeInstance(sessions: [RemoteSession(id: "remote-1")])
        let browser = makeBrowser(instance: instance)
        await browser.reloadSessions()
        browser.selectEntry(SidebarEntry.remoteID("remote-1"))
        let transcript = browser.openedRemote

        browser.selectEntry(SidebarEntry.remoteID("remote-1"))
        browser.selectEntry(SidebarEntry.remoteID("unknown"))
        browser.selectEntry("garbage")

        #expect(browser.openedRemote === transcript)
    }

    @Test("row ids round-trip to their local and remote ids")
    func rowIDsRoundTrip() {
        let id = UUID()
        #expect(SidebarEntry.localUUID(from: SidebarEntry.localID(id)) == id)
        #expect(SidebarEntry.remoteSessionID(from: SidebarEntry.remoteID("abc")) == "abc")
        #expect(SidebarEntry.localUUID(from: SidebarEntry.remoteID("abc")) == nil)
        #expect(SidebarEntry.remoteSessionID(from: SidebarEntry.localID(id)) == nil)
    }

    // MARK: Rename and delete on the instance

    @Test("renaming a session renames it on the instance and in the open conversation, in place")
    func renameSession() async throws {
        let instance = FakeInstance(sessions: [RemoteSession(id: "a", title: "A"), RemoteSession(id: "b", title: "B")])
        let browser = makeBrowser(instance: instance)
        await browser.reloadSessions()
        browser.selectEntry(SidebarEntry.remoteID("b"))

        try await browser.renameSession("b", to: "  Budget  ")
        try await browser.renameSession("b", to: "   ")

        #expect(await instance.renamed == ["Budget"])
        #expect(browser.remoteSessions.sessions.map(\.title) == ["A", "Budget"])
        #expect(browser.openedRemote?.title == "Budget")
    }

    @Test("deleting the open session deletes it on the instance, removes its row and closes it")
    func deleteOpenSession() async throws {
        let instance = FakeInstance(sessions: [RemoteSession(id: "a"), RemoteSession(id: "b")])
        let browser = makeBrowser(instance: instance)
        await browser.reloadSessions()
        browser.selectEntry(SidebarEntry.remoteID("b"))

        try await browser.deleteSession("b")

        #expect(await instance.deleted == ["b"])
        #expect(browser.remoteSessions.sessions.map(\.id) == ["a"])
        #expect(browser.openedRemote == nil)
    }

    @Test("a refused delete keeps the row and the open session")
    func refusedDelete() async {
        let instance = FakeInstance(sessions: [RemoteSession(id: "a")])
        await instance.failDeletes(with: .http(status: 409))
        let browser = makeBrowser(instance: instance)
        await browser.reloadSessions()
        browser.selectEntry(SidebarEntry.remoteID("a"))

        await #expect(throws: HermesAPIError.http(status: 409)) {
            try await browser.deleteSession("a")
        }

        #expect(browser.remoteSessions.sessions.map(\.id) == ["a"])
        #expect(browser.openedRemote?.sessionID == "a")
    }

    // MARK: Conversations saved on this device

    @Test("a conversation saved on this device can be renamed, exported and deleted")
    func localConversation() throws {
        let store = InMemoryConversationStore()
        let conversation = try store.createConversation(title: "Old chat")
        let browser = makeBrowser(store: store)
        browser.select(conversation.id)

        try browser.rename(conversation.id, to: "  Archive  ")
        try browser.rename(conversation.id, to: "  ")
        #expect(browser.summaries.first?.title == "Archive")
        #expect(browser.archived?.title == "Archive")
        #expect(browser.export(conversation.id) != nil)

        try browser.delete(conversation.id)
        #expect(browser.summaries.isEmpty)
        #expect(browser.archived == nil)
        #expect(browser.selectedID == nil)
    }
}
