import HermesAPI
import HermesChat
import HermesStore
import SwiftUI

/// Sidebar: one list of the conversations on this device and the sessions on the Hermes instance,
/// most recently used first. Local conversations show their model, open, and can be renamed or deleted.
/// A remote session opens read-only in the detail pane.
struct ConversationListView: View {
    let browser: ConversationBrowser

    @State private var renamingID: UUID?
    @State private var draftTitle = ""

    var body: some View {
        List(selection: selection) {
            ForEach(entries) { entry in
                switch entry {
                case .local(let summary):
                    localRow(summary)
                case .remote(let session):
                    remoteRow(session)
                }
            }
            if let remote = browser.remoteSessions {
                RemoteStatusRows(list: remote)
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

    private func localRow(_ summary: ConversationSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.title)
                .lineLimit(1)
            HStack(spacing: 4) {
                if let model = summary.model {
                    Text(ModelChoice.displayName(model: model, provider: summary.provider))
                        .lineLimit(1)
                    Text("·")
                }
                Text(summary.updatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(SidebarEntry.localID(summary.id))
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

    private func remoteRow(_ session: RemoteSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title ?? "Untitled session")
                .lineLimit(1)
            if let lastActive = session.lastActive {
                Text(lastActive, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(SidebarEntry.remoteID(session.id))
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
