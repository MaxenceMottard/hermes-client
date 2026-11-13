import Testing
@testable import HermesAPI

@Suite("HermesAPIPaths")
struct HermesAPIPathsTests {
    @Test("le chemin chat/completions correspond au contrat OpenAI-compatible")
    func chatCompletionsPath() {
        #expect(HermesAPIPaths.chatCompletions == "/v1/chat/completions")
    }
}
