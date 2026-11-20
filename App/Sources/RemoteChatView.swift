import HermesAPI
import HermesChat
import SwiftUI

/// A session stored on the Hermes instance, shown in the detail pane with the same message rows as a
/// local conversation. Messages can be sent: the reply streams in from the instance. Text only for now.
/// A session created outside the app is forked on the first message, see `RemoteTranscript`.
struct RemoteChatView: View {
    let transcript: RemoteTranscript

    @State private var draft = ""
    /// Id of the line at the top of the viewport. Set it to scroll there.
    @State private var scrolledID: String?
    /// Set when the reader stops on the oldest shown line; cleared once the older page is in place.
    @State private var loadingOlder = false
    @FocusState private var isComposerFocused: Bool
    /// `false` while the reader is scrolled away from the newest line: shows the scroll-to-bottom button.
    @State private var isAtBottom = true

    var body: some View {
        VStack(spacing: 0) {
            statusView

            // `defaultScrollAnchor(.bottom)` and `ScrollViewProxy.scrollTo` are not used: with a lazy stack on
            // iOS 27 the first leaves the viewport blank until the user scrolls, and the second does nothing
            // after a prepend. The scroll position is driven through `scrollPosition(id:)` instead.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcript.lines) { line in
                        MessageRow(message: ChatMessage(role: line.role, content: line.text))
                    }
                }
                .scrollTargetLayout()
                .padding()
            }
            // Before the inset, so a tap on the composer does not hide the keyboard.
            .dismissesKeyboard($isComposerFocused)
            .tracksScrollBottom($isAtBottom)
            .scrollPosition(id: $scrolledID, anchor: .top)
            // Stopping on the oldest shown line pulls in the next older page.
            .onScrollPhaseChange { _, phase in
                if phase == .idle, !loadingOlder, transcript.hasMore, transcript.state == .loaded,
                   let scrolledID, scrolledID == transcript.lines.first?.id
                {
                    loadingOlder = true
                }
            }
            .task(id: loadingOlder) {
                guard loadingOlder else { return }
                let firstShown = scrolledID
                await transcript.loadMore()
                // Older lines went above: put the line the reader was on back at the top.
                if let firstShown {
                    scrolledID = firstShown
                }
                loadingOlder = false
            }
            // A message sent from here scrolls the transcript to its end.
            .onChange(of: transcript.lines.last?.id) { oldID, lastID in
                if oldID != nil, let lastID {
                    withAnimation {
                        scrolledID = lastID
                    }
                }
            }

            // The lines scroll beneath the composer. Text only: there is no add button.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    // A session created elsewhere (web dashboard, TUI) is forked on the first message.
                    if !transcript.acceptsMessages {
                        ComposerStatus {
                            Text("Started outside the app. Your next message continues it as a new conversation.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = transcript.sendError {
                        ComposerStatus {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }

                    ChatComposer(
                        draft: $draft,
                        isFocused: $isComposerFocused,
                        model: transcript.model.map { ModelChoice(model: $0) },
                        isBusy: transcript.isSending,
                        canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        onSend: {
                            let text = draft
                            draft = ""
                            Task { await transcript.send(text) }
                        },
                        onStop: { transcript.stop() }
                    )
                }
                .scrollToBottomButton(isVisible: !isAtBottom) {
                    Task { await scrollToNewest() }
                }
            }
        }
        .navigationTitle(transcript.title ?? "Untitled session")
        .inlineNavigationTitle()
        // The browser starts the load when the session opens; this waits for it, or loads again if it was
        // never started. On iOS 27 a collapsed split view can skip or cancel this task, so the jump to the
        // newest line also runs when the first load lands.
        .task(id: transcript.sessionID) {
            if transcript.state != .loaded {
                await transcript.load()
            }
            await scrollToNewest()
        }
        .onChange(of: transcript.state) { oldState, newState in
            if oldState == .loading, newState == .loaded, scrolledID == nil {
                Task { await scrollToNewest() }
            }
        }
    }

    /// Opens the transcript on its newest line. The lazy stack estimates the height of rows it has not
    /// laid out yet, so the first jump can stop short: the position is reset and set a second time.
    private func scrollToNewest() async {
        guard let lastID = transcript.lines.last?.id else { return }
        scrolledID = lastID
        try? await Task.sleep(for: .milliseconds(10))
        scrolledID = nil
        try? await Task.sleep(for: .milliseconds(10))
        scrolledID = lastID
    }

    /// Loading and failure state, above the transcript.
    @ViewBuilder
    private var statusView: some View {
        switch transcript.state {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            ProgressView()
                .padding(.vertical, 8)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task {
                        await transcript.load()
                        await scrollToNewest()
                    }
                }
            }
            .padding()
        }
    }
}
