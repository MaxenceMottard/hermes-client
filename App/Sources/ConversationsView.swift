import HermesAPI
import HermesChat
import HermesStore
import SwiftUI

/// Chat tab: a split view with the conversation list and the open conversation.
/// A new conversation is a session created on the instance, on the model chosen in `NewConversationView`.
/// On compact widths the split view collapses into a navigation stack.
struct ConversationsView: View {
    let browser: ConversationBrowser
    /// Lists the instance models for the new conversation screen. `nil` means the name is typed by hand.
    let modelCatalog: (any ModelCatalog)?

    @State private var isChoosingModel = false
    /// Why the last action on a conversation failed, shown in an alert.
    @State private var failure: String?

    var body: some View {
        NavigationSplitView {
            ConversationListView(browser: browser, failure: $failure)
                .navigationTitle("Conversations")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New conversation", systemImage: "square.and.pencil") {
                            isChoosingModel = true
                        }
                        .disabled(browser.isCreating)
                    }
                }
        } detail: {
            Group {
                if let transcript = browser.openedRemote {
                    ChatView(transcript: transcript)
                        // A new view per session: its draft and scroll position belong to one conversation.
                        .id(transcript.sessionID)
                } else if let conversation = browser.archived {
                    ArchivedChatView(conversation: conversation)
                        .toolbar {
                            if let export = browser.export(conversation.id) {
                                ToolbarItem(placement: .primaryAction) {
                                    ExportLink(export: export)
                                }
                            }
                        }
                } else if browser.isCreating {
                    ProgressView("Starting the conversation…")
                } else {
                    ContentUnavailableView {
                        Label("No conversation open", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Pick a conversation in the list, or start a new one.")
                    } actions: {
                        Button("New conversation") {
                            isChoosingModel = true
                        }
                    }
                }
            }
            // On iPhone an open conversation fills the screen: the tab bar comes back with the list.
            .hidesTabBarWhenCompact()
        }
        .sheet(isPresented: $isChoosingModel) {
            NewConversationView(
                catalog: modelCatalog,
                preferred: browser.preferredChoice,
                defaultChoice: browser.defaultChoice
            ) { choice in
                Task {
                    do {
                        try await browser.createConversation(model: choice.model, provider: choice.provider)
                    } catch {
                        failure = "The conversation could not be started. \(Self.reason(error))"
                    }
                }
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    /// The user-facing reason of an error thrown by the browser.
    static func reason(_ error: any Error) -> String {
        HermesAPIError.from(error).errorDescription ?? "The request failed."
    }
}
