import HermesAPI
import HermesChat
import SwiftUI

/// A session stored on the Hermes instance, shown in the detail pane with the same message rows as a
/// local conversation. Read-only: continuing the session is not available yet.
struct RemoteChatView: View {
    let transcript: RemoteTranscript

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcript.lines) { line in
                        MessageRow(message: ChatMessage(role: line.role, content: line.text))
                    }
                    footer
                }
                .padding()
            }
            Text("Read-only: continuing this session on the instance is not available yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .navigationTitle(transcript.title ?? "Untitled session")
        .inlineNavigationTitle()
        .task(id: transcript.sessionID) {
            if transcript.state == .idle {
                await transcript.load()
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch transcript.state {
        case .loading:
            ProgressView()
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await transcript.load() }
                }
            }
        case .idle, .loaded:
            if transcript.hasMore {
                Button("Load more") {
                    Task { await transcript.loadMore() }
                }
            }
        }
    }
}
