import HermesChat
import SwiftUI

/// First launch shows the settings. Once configured, a split view shows the conversation list and the open chat.
/// On compact widths the split view collapses into a navigation stack.
struct ContentView: View {
    @State private var appState = AppState()
    @State private var showingSettings = false

    var body: some View {
        if let browser = appState.browser {
            NavigationSplitView {
                ConversationListView(browser: browser)
                    .navigationTitle("Conversations")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("New conversation", systemImage: "square.and.pencil") {
                                try? browser.createConversation()
                            }
                        }
                        ToolbarItem(placement: .secondaryAction) {
                            Button("Settings", systemImage: "gearshape") {
                                showingSettings = true
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
            .sheet(isPresented: $showingSettings) {
                SettingsView(appState: appState)
            }
        } else {
            SettingsView(appState: appState)
        }
    }

    private func currentTitle(in browser: ConversationBrowser) -> String {
        browser.summaries.first { $0.id == browser.selectedID }?.title ?? ConversationTitle.placeholder
    }
}
