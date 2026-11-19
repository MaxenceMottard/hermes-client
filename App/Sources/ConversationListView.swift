import HermesChat
import SwiftUI

/// Sidebar list of conversations. Selecting a row opens it. Rows can be renamed or deleted.
struct ConversationListView: View {
    let browser: ConversationBrowser

    @State private var renamingID: UUID?
    @State private var draftTitle = ""

    var body: some View {
        List(selection: selection) {
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
