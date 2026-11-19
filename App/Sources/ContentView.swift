import SwiftUI

/// Shows the settings on first launch, then the chat screen once the configuration is complete.
struct ContentView: View {
    @State private var appState = AppState()
    @State private var showingSettings = false

    var body: some View {
        if let session = appState.session {
            NavigationStack {
                ChatView(session: session)
                    .navigationTitle("Hermes")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Settings", systemImage: "gearshape") {
                                showingSettings = true
                            }
                        }
                    }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(appState: appState)
            }
        } else {
            SettingsView(appState: appState)
        }
    }
}
