import Foundation
import HermesAPI
import HermesStore
import Testing

@testable import HermesChat

@Suite("SidebarEntry.merged")
struct SidebarEntryTests {
    private func local(_ id: UUID = UUID(), updated seconds: Double) -> ConversationSummary {
        ConversationSummary(id: id, title: "local", updatedAt: Date(timeIntervalSince1970: seconds))
    }

    private func remote(_ id: String, active: Double?, started: Double? = nil) -> RemoteSession {
        RemoteSession(
            id: id,
            startedAt: started.map { Date(timeIntervalSince1970: $0) },
            lastActive: active.map { Date(timeIntervalSince1970: $0) }
        )
    }

    @Test("local and remote entries are one list, most recent interaction first")
    func mergesByInteraction() {
        let entries = SidebarEntry.merged(
            local: [local(updated: 100), local(updated: 300)],
            remote: [remote("r1", active: 200), remote("r2", active: 400)]
        )

        #expect(entries.map(\.lastInteraction?.timeIntervalSince1970) == [400, 300, 200, 100])
        #expect(entries.map(\.id).first == "remote-r2")
    }

    @Test("a remote session without lastActive is ordered by its start time")
    func fallsBackToStartedAt() {
        let conversation = UUID()
        let entries = SidebarEntry.merged(
            local: [local(conversation, updated: 150)],
            remote: [remote("r", active: nil, started: 200)]
        )

        #expect(entries.map(\.id) == ["remote-r", "local-\(conversation.uuidString)"])
        #expect(entries[0].lastInteraction == Date(timeIntervalSince1970: 200))
    }

    @Test("entries without any date go last")
    func undatedLast() {
        let entries = SidebarEntry.merged(
            local: [],
            remote: [remote("undated", active: nil), remote("dated", active: 10)]
        )

        #expect(entries.map(\.id) == ["remote-dated", "remote-undated"])
    }

    @Test("equal dates keep a stable order")
    func stableOnTies() {
        let first = SidebarEntry.merged(local: [], remote: [remote("b", active: 5), remote("a", active: 5)])
        let second = SidebarEntry.merged(local: [], remote: [remote("a", active: 5), remote("b", active: 5)])

        #expect(first == second)
        #expect(first.map(\.id) == ["remote-a", "remote-b"])
    }
}
