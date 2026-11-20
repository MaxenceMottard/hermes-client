import HermesChat
import SwiftUI

/// Root view. First launch shows the settings alone. Once configured, a tab bar shows the chat and the settings.
/// On iOS and iPadOS the tab bar also holds a separate "+" button that starts a new conversation.
struct ContentView: View {
    @State private var appState = AppState()
    @State private var selectedTab = AppTab.chat
    @State private var isChoosingModel = false

    var body: some View {
        if let browser = appState.browser {
            TabView(selection: tabSelection) {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: AppTab.chat) {
                    ConversationsView(
                        browser: browser,
                        modelCatalog: appState.modelCatalog,
                        isChoosingModel: $isChoosingModel
                    )
                }
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView(appState: appState)
                }
                #if os(iOS)
                    // The search role puts the tab in its own glass circle at the end of the tab bar.
                    // It is an action, not a screen: selecting it never shows its (empty) content.
                    Tab("New conversation", systemImage: "plus", value: AppTab.newConversation, role: .search) {
                        Color.clear
                    }
                #endif
            }
        } else {
            SettingsView(appState: appState)
        }
    }

    /// Selecting "+" switches to the chat tab and opens the new conversation screen instead of the tab.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == .newConversation {
                    selectedTab = .chat
                    isChoosingModel = true
                } else {
                    selectedTab = tab
                }
            }
        )
    }
}

/// The items of the root tab bar.
enum AppTab: Hashable {
    case chat
    case settings
    /// The "+" action of the tab bar (iOS and iPadOS only).
    case newConversation
}
