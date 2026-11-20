import Testing

@testable import HermesAPI

@Suite("HermesAPIPaths")
struct HermesAPIPathsTests {
    @Test("chat/completions path matches the OpenAI-compatible contract")
    func chatCompletionsPath() {
        #expect(HermesAPIPaths.chatCompletions == "/v1/chat/completions")
    }

    @Test("models path is /v1/models (needs-verification, kept in one constant)")
    func modelsPath() {
        #expect(HermesAPIPaths.models == "/v1/models")
    }
}
