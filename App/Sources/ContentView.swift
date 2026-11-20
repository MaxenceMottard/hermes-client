import HermesChat
import SwiftUI

/// First launch shows the settings alone. Once configured, a tab bar shows the conversations and the settings.
/// The conversations tab is a split view: the conversation list and the open chat.
/// On compact widths the split view collapses into a navigation stack.
struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        if let browser = appState.browser {
            TabView {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                    conversations(browser)
                }
                Tab("Settings", systemImage: "gearshape") {
                    SettingsView(appState: appState)
                }
            }
        } else {
            SettingsView(appState: appState)
        }
    }

    private func conversations(_ browser: ConversationBrowser) -> some View {
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
            if let session = browser.session {
                ChatView(session: session)
                    .navigationTitle(currentTitle(in: browser))
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onChange(of: browser.session?.phase) {
            browser.refresh()
        }
    }

    private func currentTitle(in browser: ConversationBrowser) -> String {
        browser.summaries.first { $0.id == browser.selectedID }?.title ?? ConversationTitle.placeholder
    }
}
