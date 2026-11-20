import Foundation
import HermesAPI
import HermesStore
import Testing

@testable import HermesChat

@Suite("SidebarEntry row content")
struct SidebarEntryRowTests {
    @Test("a local conversation is a chat with its own title")
    func localRow() {
        let entry = SidebarEntry.local(ConversationSummary(id: UUID(), title: "Trip", updatedAt: .now))

        #expect(entry.kind == .chat)
        #expect(entry.title == "Trip")
    }

    @Test("a cron session is a scheduled entry")
    func cronSession() {
        let entry = SidebarEntry.remote(RemoteSession(id: "c", title: "Price watch", source: "cron"))

        #expect(entry.kind == .scheduled)
        #expect(entry.title == "Price watch")
    }

    @Test("remote sessions from other sources, or without a source, are chats", arguments: [
        "api_server", "local", "tui", "telegram", nil,
    ])
    func otherSources(source: String?) {
        let entry = SidebarEntry.remote(RemoteSession(id: "r", source: source))

        #expect(entry.kind == .chat)
    }

    @Test("a remote session without a title gets the placeholder")
    func untitledRemote() {
        let entry = SidebarEntry.remote(RemoteSession(id: "r"))

        #expect(entry.title == SidebarEntry.untitledSession)
    }
}
