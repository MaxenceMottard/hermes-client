import HermesAPI
import HermesChat
import HermesStore
import SwiftUI

/// Sidebar: one list of the conversations on this device and the sessions on the Hermes instance,
/// most recently used first, one line per entry (an icon for its kind and the title). Local
/// conversations open and can be renamed or deleted. A remote session opens read-only in the detail pane.
struct ConversationListView: View {
    let browser: ConversationBrowser

    @State private var renamingID: UUID?
    @State private var draftTitle = ""

    var body: some View {
        List(selection: selection) {
            if !entries.isEmpty {
                Section("Recents") {
                    ForEach(entries) { entry in
                        switch entry {
                        case .local(let summary):
                            localRow(summary, entry: entry)
                        case .remote:
                            rowLabel(entry)
                        }
                    }
                }
            }
            if let remote = browser.remoteSessions {
                RemoteStatusRows(list: remote)
                    .listRowSeparator(.hidden)
            }
        }
        .task {
            await browser.remoteSessions?.reload()
        }
        .refreshable {
            await browser.remoteSessions?.reload()
        }
        .alert("Rename conversation", isPresented: isRenaming) {
            TextField("Title", text: $draftTitle)
            Button("Save") {
                if let id = renamingID {
                    try? browser.rename(id, to: draftTitle)
                }
                renamingID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingID = nil
            }
        }
    }

    private var entries: [SidebarEntry] {
        SidebarEntry.merged(
            local: browser.summaries,
            remote: browser.remoteSessions?.sessions ?? []
        )
    }

    /// One line: the icon of the entry kind and its title, truncated at the end.
    private func rowLabel(_ entry: SidebarEntry) -> some View {
        Label(entry.title, systemImage: Self.icon(for: entry.kind))
            .lineLimit(1)
            .tag(entry.id)
            .listRowSeparator(.hidden)
    }

    private static func icon(for kind: SidebarEntry.Kind) -> String {
        switch kind {
        case .chat: "bubble.left"
        case .scheduled: "clock"
        }
    }

    private func localRow(_ summary: ConversationSummary, entry: SidebarEntry) -> some View {
        rowLabel(entry)
            .contextMenu {
                Button("Rename", systemImage: "pencil") {
                    draftTitle = summary.title
                    renamingID = summary.id
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    try? browser.delete(summary.id)
                }
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    try? browser.delete(summary.id)
                }
                Button("Rename", systemImage: "pencil") {
                    draftTitle = summary.title
                    renamingID = summary.id
                }
                .tint(.indigo)
            }
    }

    /// One selection for local and remote rows. On compact widths the split view collapses into a
    /// stack, and only the list selection pushes the detail: a row outside it never opens.
    private var selection: Binding<String?> {
        Binding(
            get: { browser.selectedEntryID },
            set: { browser.selectEntry($0) }
        )
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )
    }
}

/// Footer of the sidebar for the Hermes instance: a loading indicator, an error with retry, or "Load more".
struct RemoteStatusRows: View {
    let list: RemoteSessionList

    var body: some View {
        switch list.state {
        case .loading:
            ProgressView()
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await list.reload() }
                }
            }
        case .idle, .loaded:
            if list.hasMore {
                Button("Load more") {
                    Task { await list.loadNextPage() }
                }
            }
        }
    }
}
