import HermesAPI
import HermesChat
import SwiftUI

/// Conversation screen: message list, composer, and Send / Stop.
/// The keyboard shortcuts (⌘↩, ⌘.) are in the menu bar, see `ChatMenuCommands`.
struct ChatView: View {
    let session: ChatSession
    @Binding var draft: String
    let onCommand: (ChatCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                        MessageRow(message: message)
                    }
                }
                .padding()
            }

            if session.phase == .sending {
                ProgressView()
                    .padding(.bottom, 4)
            }

            if let message = failureMessage {
                VStack(spacing: 6) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    if session.canRetry {
                        Button("Retry") {
                            Task { await session.retry() }
                        }
                    }
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 5)
                    // The multi-line field can consume ⌘↩ before the menu sees it: handle it here too.
                    // The second path is a no-op, because sending clears the draft synchronously.
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        onCommand(.send)
                        return .handled
                    }

                if session.isBusy {
                    Button("Stop", systemImage: "stop.circle.fill") {
                        onCommand(.stop)
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill") {
                        onCommand(.send)
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .disabled(!ChatCommand.send.isEnabled(isBusy: session.isBusy, draft: draft))
                }
            }
            .padding()
        }
    }
}

private extension ChatView {
    var failureMessage: String? {
        switch session.phase {
        case .failed(let error):
            error.errorDescription ?? "Unknown error"
        case .emptyReply:
            "The agent sent an empty reply."
        case .idle, .sending, .streaming:
            nil
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }
            Group {
                if message.role == "user" {
                    Text(message.content)
                } else {
                    MarkdownView(source: message.content)
                }
            }
                .padding(10)
                .background(
                    message.role == "user" ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            if message.role != "user" { Spacer(minLength: 40) }
        }
    }
}
