import HermesAPI
import HermesChat
import HermesStore
import SwiftUI

/// Sidebar: the conversations, most recently used first. Each is a session on the Hermes instance; the
/// conversations saved on this device by earlier versions of the app are listed too, marked as such.
/// Every row can be renamed or deleted, from its context menu or a swipe.
struct ConversationListView: View {
    let browser: ConversationBrowser
    /// Set to the reason when a rename or a delete fails.
    @Binding var failure: String?

    /// The conversation being renamed, and the title being typed.
    @State private var renaming: Target?
    @State private var draftTitle = ""
    /// The conversation waiting for the delete confirmation.
    @State private var deleting: Target?

    /// A row the user acts on: a session on the instance, or a conversation saved on this device.
    enum Target: Equatable {
        case remote(String)
        case local(UUID)
    }

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
            RemoteStatusRows(list: browser.remoteSessions)
        }
        .task {
            await browser.reloadSessions()
        }
        .refreshable {
            await browser.reloadSessions()
        }
        .alert("Rename conversation", isPresented: isRenaming) {
            TextField("Title", text: $draftTitle)
            Button("Save") {
                if let renaming {
                    rename(renaming, to: draftTitle)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) {
                renaming = nil
            }
        }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: isDeleting,
            titleVisibility: .visible,
            presenting: deleting
        ) { target in
            Button("Delete", role: .destructive) {
                delete(target)
            }
        } message: { target in
            switch target {
            case .remote:
                Text("It is deleted from your Hermes instance, with all its messages.")
            case .local:
                Text("It is deleted from this device.")
            }
        }
    }

    private var entries: [SidebarEntry] {
        SidebarEntry.merged(local: browser.summaries, remote: browser.remoteSessions.sessions)
    }

    private func remoteRow(_ session: RemoteSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title ?? ConversationTitle.placeholder)
                .lineLimit(1)
            if let lastActive = session.lastActive ?? session.startedAt {
                Text(lastActive, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(SidebarEntry.remoteID(session.id))
        .modifier(RowActions(
            onRename: { startRenaming(.remote(session.id), title: session.title ?? "") },
            onDelete: { deleting = .remote(session.id) }
        ))
    }

    private func localRow(_ summary: ConversationSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.title)
                .lineLimit(1)
            HStack(spacing: 4) {
                Label("On this device", systemImage: "iphone")
                    .labelStyle(.titleAndIcon)
                Text("·")
                Text(summary.updatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(SidebarEntry.localID(summary.id))
        .modifier(RowActions(
            onRename: { startRenaming(.local(summary.id), title: summary.title) },
            onDelete: { deleting = .local(summary.id) }
        ))
    }

    private func startRenaming(_ target: Target, title: String) {
        draftTitle = title
        renaming = target
    }

    private func rename(_ target: Target, to title: String) {
        switch target {
        case .local(let id):
            try? browser.rename(id, to: title)
        case .remote(let id):
            Task {
                do {
                    try await browser.renameSession(id, to: title)
                } catch {
                    failure = "The conversation could not be renamed. \(ConversationsView.reason(error))"
                }
            }
        }
    }

    private func delete(_ target: Target) {
        switch target {
        case .local(let id):
            try? browser.delete(id)
        case .remote(let id):
            Task {
                do {
                    try await browser.deleteSession(id)
                } catch {
                    failure = "The conversation could not be deleted. \(ConversationsView.reason(error))"
                }
            }
        }
    }

    /// One selection for every row. On compact widths the split view collapses into a stack, and only
    /// the list selection pushes the detail: a row outside it never opens.
    private var selection: Binding<String?> {
        Binding(
            get: { browser.selectedEntryID },
            set: { browser.selectEntry($0) }
        )
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

/// Rename and delete, in the context menu and as trailing swipe actions.
private struct RowActions: ViewModifier {
    let onRename: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Rename", systemImage: "pencil", action: onRename)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                Button("Rename", systemImage: "pencil", action: onRename)
                    .tint(.indigo)
            }
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
