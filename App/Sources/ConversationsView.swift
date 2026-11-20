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
                            _ = try? browser.createConversation()
                        }
                    }
                }
        } detail: {
            if let session = browser.session {
                ChatView(session: session)
                    .navigationTitle(currentTitle)
                    .inlineNavigationTitle()
                    .toolbar {
                        if let export = currentExport {
                            ToolbarItem(placement: .primaryAction) {
                                ShareLink(item: ConversationFile(export: export)) {
                                    Label("Export as Markdown", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                    }
            }
        }
        .onChange(of: browser.session?.phase) {
            browser.refresh()
        }
    }

    private var currentTitle: String {
        browser.summaries.first { $0.id == browser.selectedID }?.title ?? ConversationTitle.placeholder
    }

    private var currentExport: ConversationExport? {
        browser.selectedID.flatMap { browser.export($0) }
    }
}
