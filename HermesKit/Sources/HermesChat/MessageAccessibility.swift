import HermesAPI

/// Author names and spoken descriptions of messages, shared by the chat UI (VoiceOver) and the Markdown export.
public enum MessageAuthor {
    /// Name shown for a message role: "You" for the user, "Hermes" for the agent.
    /// Any other role is shown as it is.
    public static func name(for role: String) -> String {
        switch role {
        case "user": "You"
        case "assistant": "Hermes"
        default: role
        }
    }
}

/// Spoken description of a chat bubble, read by VoiceOver.
public enum MessageAccessibility {
    /// The author, then the content. A reply that has no text yet is announced as such.
    public static func label(for message: ChatMessage) -> String {
        let author = MessageAuthor.name(for: message.role)
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return "\(author), no text yet" }
        return "\(author): \(content)"
    }
}
