import Testing

@testable import HermesChat

@Suite("ChatCommand")
struct ChatCommandTests {
    @Test("new conversation is always enabled")
    func newConversationAlwaysEnabled() {
        #expect(ChatCommand.newConversation.isEnabled(isBusy: false, draft: ""))
        #expect(ChatCommand.newConversation.isEnabled(isBusy: true, draft: "text"))
    }

    @Test("send needs a non-blank draft")
    func sendNeedsDraft() {
        #expect(ChatCommand.send.isEnabled(isBusy: false, draft: "hello"))
        #expect(!ChatCommand.send.isEnabled(isBusy: false, draft: ""))
        #expect(!ChatCommand.send.isEnabled(isBusy: false, draft: "  \n\t "))
    }

    @Test("send is disabled while a reply is pending or streaming")
    func sendDisabledWhenBusy() {
        #expect(!ChatCommand.send.isEnabled(isBusy: true, draft: "hello"))
    }

    @Test("stop only applies while a reply is in progress")
    func stopOnlyWhenBusy() {
        #expect(ChatCommand.stop.isEnabled(isBusy: true, draft: ""))
        #expect(!ChatCommand.stop.isEnabled(isBusy: false, draft: "hello"))
        #expect(!ChatCommand.stop.isEnabled(isBusy: false, draft: ""))
    }
}
