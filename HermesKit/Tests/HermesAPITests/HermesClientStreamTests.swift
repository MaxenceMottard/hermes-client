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
                url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)
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
}
