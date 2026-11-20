import HermesChat
import SwiftUI

/// Chat tab: a split view with the conversation list and the open conversation.
/// A new conversation starts on the model chosen in `NewConversationView`.
/// On compact widths the split view collapses into a navigation stack.
struct ConversationsView: View {
    let browser: ConversationBrowser
    /// Lists the instance models for the new conversation screen. `nil` means the name is typed by hand.
    let modelCatalog: (any ModelCatalog)?

    @State private var isChoosingModel = false

    var body: some View {
        NavigationSplitView {
            ConversationListView(browser: browser)
                .navigationTitle("Conversations")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New conversation", systemImage: "square.and.pencil") {
                            isChoosingModel = true
                        }
                    }
                }
        } detail: {
            if let remote = browser.openedRemote {
                RemoteChatView(transcript: remote)
            } else if let session = browser.session {
                ChatView(session: session)
                    .navigationTitle(currentTitle)
                    .navigationSubtitle(session.model)
                    .inlineNavigationTitle()
                    .toolbar {
                        if let export = currentExport {
                            ToolbarItem(placement: .primaryAction) {
                                ExportLink(export: export)
                            }
                        }
                    }
            }
        }
        .onChange(of: browser.session?.phase) {
            browser.refresh()
        }
        .sheet(isPresented: $isChoosingModel) {
            NewConversationView(catalog: modelCatalog, preferredModel: browser.preferredModel) { model in
                _ = try? browser.createConversation(model: model)
            }
        }
    }

    private var currentTitle: String {
        browser.summaries.first { $0.id == browser.selectedID }?.title ?? ConversationTitle.placeholder
    }

    private var currentExport: ConversationExport? {
        browser.selectedID.flatMap { browser.export($0) }
    }
}
