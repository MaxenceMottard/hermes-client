import Foundation
import HermesStore
import Testing

@testable import HermesChat

@Suite("Conversation Markdown export")
struct ConversationExportTests {
    private func conversation(
        title: String = "Deploy notes",
        messages: [StoredMessage]
    ) -> StoredConversation {
        StoredConversation(
            id: UUID(),
            title: title,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            messages: messages
        )
    }

    @Test("the document has the title, then one block per message with its author, in order")
    func documentLayout() {
        let export = ConversationExport.make(
            from: conversation(messages: [
                StoredMessage(role: "user", content: "How do I deploy?"),
                StoredMessage(role: "assistant", content: "Run the script."),
                StoredMessage(role: "user", content: "Thanks"),
            ]))

        #expect(
            export.markdown == """
                # Deploy notes

                ## You

                How do I deploy?

                ## Hermes

                Run the script.

                ## You

                Thanks

                """)
    }

    @Test("code blocks are kept intact, including their fences and indentation")
    func codeBlocksKept() {
        let code = "```swift\nfunc run() {\n    print(\"*raw* # not a heading\")\n}\n```"
        let export = ConversationExport.make(
            from: conversation(messages: [StoredMessage(role: "assistant", content: "Here:\n\n\(code)")])
        )

        #expect(export.markdown.contains("Here:\n\n\(code)\n"))
    }

    @Test("a conversation without messages is just its title")
    func emptyConversation() {
        let export = ConversationExport.make(from: conversation(messages: []))

        #expect(export.markdown == "# Deploy notes\n")
    }

    @Test("the file name is the title with the .md extension")
    func fileNameFromTitle() {
        #expect(ConversationExport.fileName(for: "Deploy notes") == "Deploy notes.md")
    }

    @Test("characters that file systems reject are replaced in the file name")
    func fileNameSanitised() {
        #expect(ConversationExport.fileName(for: "a/b:c*d?\"e\"<f>|g\\h") == "a b c d e f g h.md")
        #expect(ConversationExport.fileName(for: "line one\nline two") == "line one line two.md")
    }

    @Test("a title with nothing usable gives a generic file name")
    func fileNameFallback() {
        #expect(ConversationExport.fileName(for: "   ") == "conversation.md")
        #expect(ConversationExport.fileName(for: "...") == "conversation.md")
        #expect(ConversationExport.fileName(for: "/") == "conversation.md")
    }
}

@MainActor
@Suite("ConversationBrowser export")
struct ConversationBrowserExportTests {
    @Test("an open conversation exports its saved messages")
    func exportsSavedMessages() throws {
        let store = InMemoryConversationStore()
        let saved = try store.createConversation(title: "Trip")
        try store.replaceMessages([StoredMessage(role: "user", content: "Hi")], inConversation: saved.id)
        let browser = ConversationBrowser(store: store, remoteSessions: RemoteSessionList(source: FakeInstance()))

        let export = browser.export(saved.id)

        #expect(export?.fileName == "Trip.md")
        #expect(export?.markdown == "# Trip\n\n## You\n\nHi\n")
    }

    @Test("an unknown conversation exports nothing")
    func unknownConversation() {
        let browser = ConversationBrowser(
            store: InMemoryConversationStore(), remoteSessions: RemoteSessionList(source: FakeInstance()))

        #expect(browser.export(UUID()) == nil)
    }
}
