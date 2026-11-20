import Foundation
import HermesAPI
import HermesStore
import Testing

@testable import HermesChat

@Suite("SidebarEntry.filtered")
struct SidebarEntrySearchTests {
    private let entries: [SidebarEntry] = [
        .local(ConversationSummary(id: UUID(), title: "Tuist preview on macOS", updatedAt: .now)),
        .remote(RemoteSession(id: "a", title: "Dashboard client Hermès")),
        .remote(RemoteSession(id: "b", title: "Price watch", source: "cron")),
        .remote(RemoteSession(id: "c")),
    ]

    @Test("the match ignores case", arguments: ["tuist", "TUIST", "TuIsT preview"])
    func ignoresCase(query: String) {
        let titles = SidebarEntry.filtered(entries, matching: query).map(\.title)

        #expect(titles == ["Tuist preview on macOS"])
    }

    @Test("the match ignores accents")
    func ignoresAccents() {
        let titles = SidebarEntry.filtered(entries, matching: "hermes").map(\.title)

        #expect(titles == ["Dashboard client Hermès"])
    }

    @Test("a part of a word matches, and the order is kept")
    func substringKeepsOrder() {
        let titles = SidebarEntry.filtered(entries, matching: "o").map(\.title)

        #expect(titles == ["Tuist preview on macOS", "Dashboard client Hermès", "Untitled session"])
    }

    @Test("an empty or blank query keeps every entry", arguments: ["", "   ", "\n"])
    func blankQuery(query: String) {
        #expect(SidebarEntry.filtered(entries, matching: query) == entries)
    }

    @Test("surrounding whitespace is ignored")
    func trimsQuery() {
        let titles = SidebarEntry.filtered(entries, matching: "  price ").map(\.title)

        #expect(titles == ["Price watch"])
    }

    @Test("no match gives an empty list")
    func noMatch() {
        #expect(SidebarEntry.filtered(entries, matching: "golf").isEmpty)
    }
}
