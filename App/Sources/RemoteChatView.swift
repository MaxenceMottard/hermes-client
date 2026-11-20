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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Sentinel at the top: appearing here means the reader reached the oldest shown line.
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                loadOlderIfNeeded(proxy)
                            }
                        topFooter
                        ForEach(transcript.lines) { line in
                            MessageRow(message: ChatMessage(role: line.role, content: line.text))
                                .id(line.id)
                        }
                    }
                    .padding()
                }
                // Opens on the newest message and stays there while older pages are added above it.
                .defaultScrollAnchor(.bottom)
                // Scrolling near the top pulls in the next older page.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offsetY in
                    if offsetY < 200 {
                        loadOlderIfNeeded(proxy)
                    }
                }
                // A message sent from here scrolls the transcript back to the bottom.
                .onChange(of: transcript.lines.last?.id) { _, lastID in
                    if let lastID {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
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

    /// Older messages are loaded above the first shown line, which keeps its place on screen.
    private func loadOlderIfNeeded(_ proxy: ScrollViewProxy) {
        guard transcript.hasMore, transcript.state == .loaded else { return }
        let firstShown = transcript.lines.first?.id
        Task {
            await transcript.loadMore()
            if let firstShown {
                proxy.scrollTo(firstShown, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private var topFooter: some View {
        switch transcript.state {
        case .idle, .loaded:
            EmptyView()
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
        }
    }
}
