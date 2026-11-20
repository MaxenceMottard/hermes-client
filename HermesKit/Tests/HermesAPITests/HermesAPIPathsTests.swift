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

    @Test("sessions path is /api/sessions (read from the gateway source)")
    func sessionsPath() {
        #expect(HermesAPIPaths.sessions == "/api/sessions")
    }

    @Test("fork path is /api/sessions/{id}/fork (read from the gateway source)")
    func sessionForkPath() {
        #expect(HermesAPIPaths.sessionFork("abc") == "/api/sessions/abc/fork")
    }

    @Test("one session is /api/sessions/{id}, its chat stream /api/sessions/{id}/chat/stream")
    func sessionPaths() {
        #expect(HermesAPIPaths.session("abc") == "/api/sessions/abc")
        #expect(HermesAPIPaths.sessionChatStream("abc") == "/api/sessions/abc/chat/stream")
    }
}
