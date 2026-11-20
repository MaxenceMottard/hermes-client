import HermesAPI
import HermesChat
import HermesStore
import SwiftUI

/// A conversation saved on this device by an earlier version of the app, read-only: the instance has no
/// copy of it, so it cannot be continued. It can still be exported, renamed or deleted from the list.
struct ArchivedChatView: View {
    let conversation: StoredConversation

    var body: some View {
        // A plain stack: `defaultScrollAnchor(.bottom)` leaves a lazy stack blank on iOS 27.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(conversation.messages.enumerated()), id: \.offset) { _, message in
                    MessageRow(message: ChatMessage(role: message.role, content: message.content))
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerStatus {
                Text("Saved on this device only. Start a new conversation to continue on your Hermes instance.")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .navigationTitle(conversation.title)
        .inlineNavigationTitle()
    }
}
