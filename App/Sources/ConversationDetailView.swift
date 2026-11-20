import HermesChat
import SwiftUI

/// Detail column of the chat split view: the open conversation, titled with its summary title.
struct ConversationDetailView: View {
    let browser: ConversationBrowser

    var body: some View {
        if let session = browser.session {
            ChatView(session: session)
                .navigationTitle(currentTitle)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var currentTitle: String {
        browser.summaries.first { $0.id == browser.selectedID }?.title ?? ConversationTitle.placeholder
    }
}
