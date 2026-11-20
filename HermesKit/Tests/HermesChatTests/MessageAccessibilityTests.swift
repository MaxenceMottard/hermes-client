import HermesAPI
import Testing

@testable import HermesChat

@Suite("Message accessibility")
struct MessageAccessibilityTests {
    @Test("the user is named You and the agent Hermes")
    func authorNames() {
        #expect(MessageAuthor.name(for: "user") == "You")
        #expect(MessageAuthor.name(for: "assistant") == "Hermes")
        #expect(MessageAuthor.name(for: "tool") == "tool")
    }

    @Test("a bubble is announced as its author, then its content")
    func labelHasAuthorAndContent() {
        let label = MessageAccessibility.label(for: ChatMessage(role: "user", content: "  Hello there \n"))
        #expect(label == "You: Hello there")
    }

    @Test("a reply without text yet is announced as such")
    func labelForEmptyReply() {
        let label = MessageAccessibility.label(for: ChatMessage(role: "assistant", content: ""))
        #expect(label == "Hermes, no text yet")
    }
}
