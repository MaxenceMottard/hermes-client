import Foundation
import Testing

@testable import HermesAPI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A scripted reply returned by `MockURLProtocol`.
struct MockReply: Sendable {
    var status = 200
    var chunks: [Data] = []
    /// `false`: the response stays open (useful to test cancellation).
    var finish = true
    var failure: URLError?
    /// The final URL of the response, when it differs from the request URL (for example after a redirect).
    var responseURL: URL?
}

/// Intercepts the requests of the test session. Global state: the suite is `.serialized`.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> MockReply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    nonisolated(unsafe) static var stopCount = 0

    static func reset() {
        responder = nil
        requests = []
        bodies = []
        stopCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.readBody(request))

        let reply = Self.responder?(request) ?? MockReply(status: 500)
        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: reply.responseURL ?? url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if reply.finish {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.stopCount += 1
    }

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite("HermesClient.streamChat", .serialized)
struct HermesClientStreamTests {
    private let baseURL = URL(string: "https://hermes.example.test") ?? URL(filePath: "/")
    private let apiKey = "test-key-123"
    private let messages = [ChatMessage(role: "user", content: "Hi")]

    init() {
        MockURLProtocol.reset()
    }

    private func makeClient(baseURL: URL? = nil) -> HermesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return HermesClient(
            configuration: HermesClientConfiguration(baseURL: baseURL ?? self.baseURL, apiKey: apiKey),
            session: session
        )
    }

    private func fixtureData(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }

    private func collect(_ stream: AsyncThrowingStream<String, any Error>) async throws -> [String] {
        var deltas: [String] = []
        for try await delta in stream {
            deltas.append(delta)
        }
        return deltas
    }

    @Test("the request is an authenticated POST with stream: true, to /v1/chat/completions")
    func requestShape() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data("data: [DONE]\n".utf8)]) }

        _ = try await collect(makeClient().streamChat(model: "hermes-test-model", messages: messages))

        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://hermes.example.test/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")

        let body = try #require(try JSONSerialization.jsonObject(with: MockURLProtocol.bodies[0]) as? [String: Any])
        #expect(Set(body.keys) == ["model", "messages", "stream"])
        #expect(body["stream"] as? Bool == true)
        #expect(body["model"] as? String == "hermes-test-model")
    }

    @Test("a base URL with a trailing slash does not produce a double slash")
    func trailingSlashBaseURL() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data("data: [DONE]\n".utf8)]) }
        let base = URL(string: "https://hermes.example.test/") ?? URL(filePath: "/")

        _ = try await collect(makeClient(baseURL: base).streamChat(model: "m", messages: messages))

        #expect(
            MockURLProtocol.requests.first?.url?.absoluteString == "https://hermes.example.test/v1/chat/completions")
    }

    @Test("deltas are emitted in order and the stream ends on [DONE]")
    func deltasInOrder() async throws {
        let sse = try fixtureData("chat_stream", "sse")
        MockURLProtocol.responder = { _ in MockReply(chunks: [sse]) }

        let deltas = try await collect(makeClient().streamChat(model: "m", messages: messages))

        #expect(deltas == ["Bon", "jour"])
    }

    @Test("cancelling the consuming task cancels the network request")
    func cancellationStopsRequest() async throws {
        let first = Data("data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"A\"}}]}\n\n".utf8)
        MockURLProtocol.responder = { _ in MockReply(chunks: [first], finish: false) }
        let stream = makeClient().streamChat(model: "m", messages: messages)

        let consumer = Task {
            var received: [String] = []
            for try await delta in stream {
                received.append(delta)
            }
            return received
        }

        // Let the request start and receive the first delta, then cancel.
        for _ in 0..<100 where MockURLProtocol.requests.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()
        _ = try? await consumer.value

        for _ in 0..<200 where MockURLProtocol.stopCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(MockURLProtocol.stopCount > 0)
    }

    @Test("no automatic retry on the POST")
    func noRetryOnFailure() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 500) }

        await #expect(throws: HermesAPIError.self) {
            _ = try await collect(makeClient().streamChat(model: "m", messages: messages))
        }
        #expect(MockURLProtocol.requests.count == 1)
    }

    @Test("401 maps to unauthorized, without leaking the key in the message")
    func unauthorized() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 401) }

        do {
            _ = try await collect(makeClient().streamChat(model: "m", messages: messages))
            Issue.record("a 401 error was expected")
        } catch let error as HermesAPIError {
            #expect(error == .unauthorized)
            #expect(!(error.errorDescription ?? "").contains(apiKey))
        }
    }

    @Test("404 maps to notFound")
    func notFound() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 404) }
        await #expect(throws: HermesAPIError.notFound) {
            _ = try await collect(makeClient().streamChat(model: "m", messages: messages))
        }
    }

    @Test("URLError.timedOut maps to timeout")
    func timeout() async throws {
        MockURLProtocol.responder = { _ in MockReply(failure: URLError(.timedOut)) }
        await #expect(throws: HermesAPIError.timeout) {
            _ = try await collect(makeClient().streamChat(model: "m", messages: messages))
        }
    }

    @Test("an invalid JSON chunk maps to invalidResponse, without a crash")
    func invalidChunk() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data("data: {not json\n\n".utf8)]) }
        await #expect(throws: HermesAPIError.invalidResponse) {
            _ = try await collect(makeClient().streamChat(model: "m", messages: messages))
        }
    }

    // MARK: chat (non-streaming)
    // Lives in the same suite as the streaming tests: they share MockURLProtocol's global state.

    @Test("chat returns choices[0].message.content and sends stream: false")
    func chatReturnsContent() async throws {
        let json = try fixtureData("chat_completion", "json")
        MockURLProtocol.responder = { _ in MockReply(chunks: [json]) }

        let text = try await makeClient().chat(model: "m", messages: messages)

        #expect(text == "Hello, how can I help?")
        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
        let body = try #require(try JSONSerialization.jsonObject(with: MockURLProtocol.bodies[0]) as? [String: Any])
        #expect(body["stream"] as? Bool == false)
    }

    @Test("a response without choices maps to invalidResponse")
    func chatWithoutChoices() async throws {
        let json = Data(#"{"model":"m","choices":[]}"#.utf8)
        MockURLProtocol.responder = { _ in MockReply(chunks: [json]) }
        await #expect(throws: HermesAPIError.invalidResponse) {
            _ = try await makeClient().chat(model: "m", messages: messages)
        }
    }

    @Test("chat: 401 maps to unauthorized, and no retry happens")
    func chatUnauthorized() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 401) }
        await #expect(throws: HermesAPIError.unauthorized) {
            _ = try await makeClient().chat(model: "m", messages: messages)
        }
        #expect(MockURLProtocol.requests.count == 1)
    }

    @Test("chat: URLError.timedOut maps to timeout")
    func chatTimeout() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responder = { _ in MockReply(failure: URLError(.timedOut)) }
        await #expect(throws: HermesAPIError.timeout) {
            _ = try await makeClient().chat(model: "m", messages: messages)
        }
    }

    @Test("the health check is an authenticated GET to /health, without a body")
    func healthRequestShape() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data(#"{"status":"ok"}"#.utf8)]) }

        try await makeClient().healthCheck()

        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://hermes.example.test/health")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(MockURLProtocol.bodies.first?.isEmpty == true)
    }

    @Test("a JSON object body with a 200 status is a successful health check")
    func healthSuccess() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data(#"{"status":"ok"}"#.utf8)]) }
        try await makeClient().healthCheck()
    }

    @Test("a base URL with a trailing slash does not produce a double slash in the health check")
    func healthTrailingSlash() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data(#"{"status":"ok"}"#.utf8)]) }
        let base = URL(string: "https://hermes.example.test/") ?? URL(filePath: "/")
        try await makeClient(baseURL: base).healthCheck()
        #expect(MockURLProtocol.requests.first?.url?.absoluteString == "https://hermes.example.test/health")
    }

    @Test("a non-JSON body (for example an HTML login page) maps to invalidResponse")
    func healthHTMLBody() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data("<html>Log in</html>".utf8)]) }
        await #expect(throws: HermesAPIError.invalidResponse) {
            try await makeClient().healthCheck()
        }
    }

    @Test("a JSON body that is not an object maps to invalidResponse")
    func healthNonObjectBody() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data("[1,2]".utf8)]) }
        await #expect(throws: HermesAPIError.invalidResponse) {
            try await makeClient().healthCheck()
        }
    }

    @Test("an empty 200 body maps to invalidResponse")
    func healthEmptyBody() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: []) }
        await #expect(throws: HermesAPIError.invalidResponse) {
            try await makeClient().healthCheck()
        }
    }

    @Test("a response served from another URL (access gate redirect) maps to invalidResponse")
    func healthRedirectedResponse() async throws {
        let login = URL(string: "https://hermes.example.test/login") ?? URL(filePath: "/")
        MockURLProtocol.responder = { _ in
            MockReply(chunks: [Data(#"{"status":"ok"}"#.utf8)], responseURL: login)
        }
        await #expect(throws: HermesAPIError.invalidResponse) {
            try await makeClient().healthCheck()
        }
    }

    @Test("a chat response redirected to another URL maps to invalidResponse, never a success")
    func chatRedirectedResponse() async throws {
        let login = URL(string: "https://hermes.example.test/login") ?? URL(filePath: "/")
        let json = Data(#"{"model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}]}"#.utf8)
        MockURLProtocol.responder = { _ in MockReply(chunks: [json], responseURL: login) }
        await #expect(throws: HermesAPIError.invalidResponse) {
            _ = try await makeClient().chat(model: "m", messages: messages)
        }
    }

    @Test("a 302 status (redirect not followed) maps to http(status: 302)")
    func healthRedirectStatus() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 302) }
        await #expect(throws: HermesAPIError.http(status: 302)) {
            try await makeClient().healthCheck()
        }
    }

    @Test("health: 401 maps to unauthorized, 404 to notFound, 500 to http(status:)")
    func healthStatusErrors() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 401) }
        await #expect(throws: HermesAPIError.unauthorized) {
            try await makeClient().healthCheck()
        }
        MockURLProtocol.responder = { _ in MockReply(status: 404) }
        await #expect(throws: HermesAPIError.notFound) {
            try await makeClient().healthCheck()
        }
        MockURLProtocol.responder = { _ in MockReply(status: 500) }
        await #expect(throws: HermesAPIError.http(status: 500)) {
            try await makeClient().healthCheck()
        }
    }

    @Test("health: URLError.timedOut maps to timeout, and a connection failure to network")
    func healthTransportErrors() async throws {
        MockURLProtocol.responder = { _ in MockReply(failure: URLError(.timedOut)) }
        await #expect(throws: HermesAPIError.timeout) {
            try await makeClient().healthCheck()
        }
        MockURLProtocol.responder = { _ in MockReply(failure: URLError(.cannotConnectToHost)) }
        await #expect(throws: HermesAPIError.network) {
            try await makeClient().healthCheck()
        }
    }

    @Test("listModels: a 200 with data[].id returns the IDs in order")
    func listModelsSuccess() async throws {
        let json = Data(#"{"object":"list","data":[{"id":"hermes-agent","object":"model"},{"id":"fast","object":"model"}]}"#.utf8)
        MockURLProtocol.responder = { _ in MockReply(chunks: [json]) }

        let result = try await makeClient().listModels()

        #expect(result == .models(["hermes-agent", "fast"]))
        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://hermes.example.test/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
        #expect(MockURLProtocol.bodies.first?.isEmpty == true)
    }

    @Test("listModels: a 404 returns the fallback with notFound")
    func listModelsNotFound() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 404) }
        let result = try await makeClient().listModels()
        #expect(result == .fallback(.notFound))
    }

    @Test("listModels: a network failure returns the fallback with network")
    func listModelsNetwork() async throws {
        MockURLProtocol.responder = { _ in MockReply(failure: URLError(.cannotConnectToHost)) }
        let result = try await makeClient().listModels()
        #expect(result == .fallback(.network))
    }

    @Test("listModels: a timeout returns the fallback with timeout")
    func listModelsTimeout() async throws {
        MockURLProtocol.responder = { _ in MockReply(failure: URLError(.timedOut)) }
        let result = try await makeClient().listModels()
        #expect(result == .fallback(.timeout))
    }

    @Test("listModels: a 401 returns the fallback with unauthorized")
    func listModelsUnauthorized() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 401) }
        let result = try await makeClient().listModels()
        #expect(result == .fallback(.unauthorized))
    }

    @Test("listModels: a non-JSON body (login page) returns the fallback with invalidResponse")
    func listModelsHTMLBody() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data("<html>Log in</html>".utf8)]) }
        let result = try await makeClient().listModels()
        #expect(result == .fallback(.invalidResponse))
    }

    @Test("listModels: a JSON body without data[].id returns the fallback with invalidResponse")
    func listModelsUnexpectedJSON() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data(#"{"models":["a"]}"#.utf8)]) }
        let result = try await makeClient().listModels()
        #expect(result == .fallback(.invalidResponse))
    }

    @Test("listModels: an empty data array returns the fallback with invalidResponse")
    func listModelsEmpty() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data(#"{"object":"list","data":[]}"#.utf8)]) }
        let result = try await makeClient().listModels()
        #expect(result == .fallback(.invalidResponse))
    }

    @Test("listModels: a response served from another URL returns the fallback with invalidResponse")
    func listModelsRedirected() async throws {
        let login = URL(string: "https://hermes.example.test/login") ?? URL(filePath: "/")
        MockURLProtocol.responder = { _ in
            MockReply(chunks: [Data(#"{"object":"list","data":[{"id":"a"}]}"#.utf8)], responseURL: login)
        }
        let result = try await makeClient().listModels()
        #expect(result == .fallback(.invalidResponse))
    }
    @Test("listModelOptions: providers grouped as listed, without unusable ones or unavailable models")
    func listModelOptionsSuccess() async throws {
        let json = try fixtureData("model_options", "json")
        MockURLProtocol.responder = { _ in MockReply(chunks: [json]) }

        let result = try await makeClient().listModelOptions()

        #expect(
            result
                == .options(
                    ModelOptions(
                        providers: [
                            ModelProviderOption(
                                slug: "anthropic", name: "Anthropic",
                                models: ["claude-opus-test", "claude-sonnet-test"], isCurrent: true),
                            ModelProviderOption(slug: "openai", name: "OpenAI", models: ["gpt-test"]),
                        ],
                        currentModel: "claude-opus-test",
                        currentProvider: "anthropic"
                    )))
        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://hermes.example.test/api/model/options?include_unconfigured=false")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
    }

    @Test("listModelOptions: a 404 returns the fallback with notFound")
    func listModelOptionsNotFound() async throws {
        MockURLProtocol.responder = { _ in MockReply(status: 404) }
        let result = try await makeClient().listModelOptions()
        #expect(result == .fallback(.notFound))
    }

    @Test("listModelOptions: a login page returns the fallback with invalidResponse")
    func listModelOptionsHTML() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data("<html>Log in</html>".utf8)]) }
        let result = try await makeClient().listModelOptions()
        #expect(result == .fallback(.invalidResponse))
    }

    @Test("listModelOptions: a catalog with no usable provider returns the fallback with invalidResponse")
    func listModelOptionsNoUsableProvider() async throws {
        let json = Data(#"{"providers":[{"slug":"xai","models":["grok"],"authenticated":false}]}"#.utf8)
        MockURLProtocol.responder = { _ in MockReply(chunks: [json]) }
        let result = try await makeClient().listModelOptions()
        #expect(result == .fallback(.invalidResponse))
    }

    @Test("streamChat sends the provider with the model when one is given")
    func streamChatSendsProvider() async throws {
        MockURLProtocol.responder = { _ in MockReply(chunks: [Data("data: [DONE]\n".utf8)]) }

        _ = try await collect(makeClient().streamChat(model: "claude-opus-test", provider: "anthropic", messages: messages))

        let body = try #require(MockURLProtocol.bodies.first)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "claude-opus-test")
        #expect(object["provider"] as? String == "anthropic")
    }
}
