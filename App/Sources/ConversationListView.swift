import HermesChat
import SwiftUI

/// Sidebar list of conversations. Selecting a row opens it. Rows can be renamed or deleted.
/// The sessions stored on the Hermes instance are listed above the local conversations, read-only for now.
struct ConversationListView: View {
    let browser: ConversationBrowser

    @State private var renamingID: UUID?
    @State private var draftTitle = ""

    var body: some View {
        List(selection: selection) {
            if let remote = browser.remoteSessions {
                Section("Hermes instance") {
                    RemoteSessionRows(list: remote)
                }
            }
            Section("On this device") {
                ForEach(browser.summaries) { summary in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.title)
                            .lineLimit(1)
                        Text(summary.updatedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(summary.id)
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
                .onDelete(perform: delete)
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

    private var selection: Binding<UUID?> {
        Binding(
            get: { browser.selectedID },
            set: { browser.select($0) }
        )
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let id = browser.summaries[index].id
            try? browser.delete(id)
        }
    }
}

/// Rows of the sessions stored on the Hermes instance: the sessions, then a loading, error or "load more" row.
struct RemoteSessionRows: View {
    let list: RemoteSessionList

    var body: some View {
        ForEach(list.sessions) { session in
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? "Untitled session")
                    .lineLimit(1)
                if let lastActive = session.lastActive {
                    Text(lastActive, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
