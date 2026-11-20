import HermesAPI
import HermesChat
import SwiftUI

/// A session stored on the Hermes instance, shown in the detail pane with the same message rows as a
/// local conversation. Messages can be sent: the reply streams in from the instance. Text only for now.
/// A session created outside the app is forked on the first message, see `RemoteTranscript`.
struct RemoteChatView: View {
    let transcript: RemoteTranscript

    @State private var draft = ""
    /// Where the transcript is scrolled. While the reader scrolls it holds the id of the line at the top of
    /// the viewport; set it to scroll there, or to the end.
    @State private var position = ScrollPosition(idType: String.self)
    /// Further tries left for a scroll to the end, checked when the scroll stops: lines not laid out yet
    /// have estimated heights, so the first scroll can stop short.
    @State private var endRetries = 0
    /// Set when the reader stops on the oldest shown line; cleared once the older page is in place.
    @State private var loadingOlder = false
    @FocusState private var isComposerFocused: Bool
    /// `false` while the reader is scrolled away from the newest line: shows the scroll-to-bottom button.
    @State private var isAtBottom = true
    /// Top of the composer inset on screen: the visible part of the transcript ends there.
    @State private var composerTop = CGFloat.greatestFiniteMagnitude

    var body: some View {
        VStack(spacing: 0) {
            statusView

            // `defaultScrollAnchor(.bottom)` and `ScrollViewProxy.scrollTo` are not used: with a lazy stack on
            // iOS 27 the first leaves the viewport blank until the user scrolls, and the second does nothing
            // after a prepend. The scroll position is driven through `scrollPosition(_:anchor:)` instead.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(transcript.lines) { line in
                        MessageRow(message: ChatMessage(role: line.role, content: line.text))
                    }
                }
                .scrollTargetLayout()
                .padding()

                ScrollBottomMarker(visibleEnd: composerTop, isAtBottom: $isAtBottom) {
                    scrollToEnd(animation: .smooth(duration: 0.25))
                }
            }
            // Before the inset, so a tap on the composer does not hide the keyboard.
            .dismissesKeyboard($isComposerFocused)
            .scrollPosition($position, anchor: .top)
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting:
                    // The reader took over: a scroll to the end under way is not finished.
                    endRetries = 0
                case .idle:
                    // A scroll to the end that stopped short goes on from there.
                    if endRetries > 0 {
                        if isAtBottom {
                            endRetries = 0
                        } else {
                            endRetries -= 1
                            scrollToEnd(animation: .smooth(duration: 0.2))
                        }
                    }
                    // Stopping on the oldest shown line pulls in the next older page.
                    if !loadingOlder, transcript.hasMore, transcript.state == .loaded,
                       let topID = position.viewID(type: String.self), topID == transcript.lines.first?.id
                    {
                        loadingOlder = true
                    }
                default:
                    break
                }
            }
            .task(id: loadingOlder) {
                guard loadingOlder else { return }
                let firstShown = position.viewID(type: String.self)
                await transcript.loadMore()
                // Older lines went above: put the line the reader was on back at the top.
                if let firstShown {
                    position.scrollTo(id: firstShown, anchor: .top)
                }
                loadingOlder = false
            }
            // A message sent from here scrolls the transcript to its end.
            .onChange(of: transcript.lines.last?.id) { oldID, lastID in
                if oldID != nil, lastID != nil {
                    endRetries = 2
                    scrollToEnd(animation: .default)
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
                .reportsTop($composerTop)
                .scrollToBottomButton(isVisible: !isAtBottom) {
                    endRetries = 2
                    scrollToEnd(animation: .smooth(duration: 0.35))
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
            if oldState == .loading, newState == .loaded, position.viewID == nil, position.edge == nil {
                Task { await scrollToNewest() }
            }
        }
    }

    /// Scrolls to the end of the transcript in one move, so it can be animated: the bottom of the newest
    /// line comes just above the composer, however tall the line is.
    ///
    /// Setting the position to the value it already holds does nothing. After a scroll to the bottom edge
    /// that the reader has not moved from, the bottom of the last line is asked for instead.
    private func scrollToEnd(animation: Animation?) {
        guard let lastID = transcript.lines.last?.id else { return }
        var target = position
        if target.edge == .bottom {
            target.scrollTo(id: lastID, anchor: .bottom)
        } else {
            target.scrollTo(edge: .bottom)
        }
        withAnimation(animation) {
            position = target
        }
    }

    /// Opens the transcript on its newest line. The lazy stack estimates the height of rows it has not
    /// laid out yet, so the first jump can stop short: the end is asked for twice more, each time with a
    /// different value so the position changes.
    private func scrollToNewest() async {
        guard let lastID = transcript.lines.last?.id else { return }
        position.scrollTo(id: lastID, anchor: .top)
        try? await Task.sleep(for: .milliseconds(10))
        position.scrollTo(edge: .bottom)
        try? await Task.sleep(for: .milliseconds(10))
        position.scrollTo(id: lastID, anchor: .bottom)
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
