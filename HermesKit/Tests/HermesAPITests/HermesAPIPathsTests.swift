import Testing

@testable import HermesAPI

@Suite("HermesAPIPaths")
struct HermesAPIPathsTests {
    @Test("chat/completions path matches the OpenAI-compatible contract")
    func chatCompletionsPath() {
        #expect(HermesAPIPaths.chatCompletions == "/v1/chat/completions")
    }
}
