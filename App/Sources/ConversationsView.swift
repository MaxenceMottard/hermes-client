import HermesChat
import SwiftUI

/// Chat tab: a split view with the conversation list and the open conversation.
/// On compact widths the split view collapses into a navigation stack.
/// The draft lives here so that the menu bar can send it with ⌘↩.
struct ConversationsView: View {
    let browser: ConversationBrowser
    @State private var draft = ""

    var body: some View {
        NavigationSplitView {
            ConversationListView(browser: browser)
                .navigationTitle("Conversations")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New conversation", systemImage: "square.and.pencil") {
                            perform(.newConversation)
                        }
                    }
                }
        } detail: {
            if let session = browser.session {
                ChatView(session: session, draft: $draft, onCommand: perform)
                    .navigationTitle(currentTitle)
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
        .focusedSceneValue(\.chatMenuActions, menuActions)
    }

    private var currentTitle: String {
        browser.summaries.first { $0.id == browser.selectedID }?.title ?? ConversationTitle.placeholder
    }

    private var currentExport: ConversationExport? {
        browser.selectedID.flatMap { browser.export($0) }
    }

    private var menuActions: ChatMenuActions {
        let isBusy = browser.session?.isBusy ?? false
        return ChatMenuActions(
            enabled: Set(ChatCommand.allCases.filter { $0.isEnabled(isBusy: isBusy, draft: draft) }),
            perform: perform
        )
    }

    /// Runs a command if it is enabled in the current state. Shared by the toolbar, the chat view and the menu bar.
    private func perform(_ command: ChatCommand) {
        let isBusy = browser.session?.isBusy ?? false
        guard command.isEnabled(isBusy: isBusy, draft: draft) else { return }
        switch command {
        case .newConversation:
            _ = try? browser.createConversation()
        case .send:
            guard let session = browser.session else { return }
            let text = draft
            draft = ""
            Task { await session.send(text) }
        case .stop:
            browser.session?.stop()
        }
    }
}
