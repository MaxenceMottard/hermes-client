import Foundation

/// The commands a user can trigger from the keyboard or the menu bar in a conversation.
public enum ChatCommand: CaseIterable, Hashable, Sendable {
    /// Creates a conversation and opens it. Always available.
    case newConversation
    /// Sends the draft message. Needs a non-blank draft and no reply in progress.
    case send
    /// Stops the reply in progress. Only applies while a reply is pending or streaming.
    case stop

    /// Whether the command applies in the given state.
    public func isEnabled(isBusy: Bool, draft: String) -> Bool {
        switch self {
        case .newConversation:
            true
        case .send:
            !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stop:
            isBusy
        }
    }
}
