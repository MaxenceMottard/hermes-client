import HermesChat
import SwiftUI

/// Chat tab: a split view with the conversation list and the open conversation.
/// On compact widths the split view collapses into a navigation stack.
struct ConversationsView: View {
    let browser: ConversationBrowser

    var body: some View {
        NavigationSplitView {
            ConversationListView(browser: browser)
                .navigationTitle("Conversations")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New conversation", systemImage: "square.and.pencil") {
                            try? browser.createConversation()
                        }
                    }
                }
        } detail: {
            ConversationDetailView(browser: browser)
        }
        .onChange(of: browser.session?.phase) {
            browser.refresh()
        }
    }
}
