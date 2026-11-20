import Foundation
import HermesStore

/// A conversation written as a Markdown document, ready to be saved or shared.
public struct ConversationExport: Equatable, Sendable {
    public let title: String
    /// File name with the `.md` extension, derived from the title.
    public let fileName: String
    public let markdown: String

    public init(title: String, fileName: String, markdown: String) {
        self.title = title
        self.fileName = fileName
        self.markdown = markdown
    }

    /// The Markdown document of a conversation.
    ///
    /// The title is a level-1 heading. Each message is a block: its author as a level-2 heading, then its content
    /// exactly as stored, so code blocks are kept intact. Messages keep their order.
    public static func make(from conversation: StoredConversation) -> ConversationExport {
        var blocks = ["# \(conversation.title)"]
        for message in conversation.messages {
            blocks.append("## \(MessageAuthor.name(for: message.role))\n\n\(message.content)")
        }
        return ConversationExport(
            title: conversation.title,
            fileName: fileName(for: conversation.title),
            markdown: blocks.joined(separator: "\n\n") + "\n"
        )
    }

    /// A file name for a title: characters that file systems reject are replaced, and the name ends in `.md`.
    /// A title with nothing usable gives `conversation.md`.
    public static func fileName(for title: String) -> String {
        let forbidden: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        let cleaned = String(
            title.map { character -> Character in
                forbidden.contains(character) || character.isNewline ? " " : character
            }
        )
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let base = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ".")).trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "conversation" : base) + ".md"
    }
}
