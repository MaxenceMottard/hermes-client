import HermesChat
import SwiftUI

/// Sidebar list of conversations. Selecting a row opens it in the chat view.
struct ConversationListView: View {
    let browser: ConversationBrowser

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
            }
            .onDelete(perform: delete)
        }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { browser.selectedID },
            set: { browser.select($0) }
        )
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let id = browser.summaries[index].id
            try? browser.delete(id)
        }
    }
}
