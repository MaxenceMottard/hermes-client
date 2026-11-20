import HermesAPI
import HermesChat
import SwiftUI

/// A session stored on the Hermes instance, shown in the detail pane with the same message rows as a
/// local conversation. Messages can be sent: the reply streams in from the instance. Text only for now.
struct RemoteChatView: View {
    let transcript: RemoteTranscript

    @State private var draft = ""

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

            if transcript.isSending {
                ProgressView()
                    .padding(.bottom, 4)
            }

            if let error = transcript.sendError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 5)

                if transcript.isSending {
                    Button("Stop", systemImage: "stop.circle.fill") {
                        transcript.stop()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill") {
                        let text = draft
                        draft = ""
                        Task { await transcript.send(text) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
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
