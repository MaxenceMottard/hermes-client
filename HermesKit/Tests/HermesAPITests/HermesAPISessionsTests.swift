import Foundation
import Testing

@testable import HermesAPI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A scripted reply for `SessionsURLProtocol`.
struct SessionsReply: Sendable {
    var status = 200
    var body = Data()
    var failure: URLError?
    /// The final URL of the response, when it differs from the request URL (for example after a redirect).
    var responseURL: URL?
}

/// Intercepts the requests of the sessions suite only. It has its own state, so that it does not
/// race with the suites that use `MockURLProtocol`.
final class SessionsURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> SessionsReply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        responder = nil
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let reply = Self.responder?(request) ?? SessionsReply(status: 500)
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
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("HermesClient.listSessions", .serialized)
struct HermesAPISessionsTests {
    let baseURL = URL(string: "https://hermes.example.test") ?? URL(filePath: "/")

    init() {
        SessionsURLProtocol.reset()
    }

    func makeClient(baseURL: URL? = nil) -> HermesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionsURLProtocol.self]
        return HermesClient(
            configuration: HermesClientConfiguration(
                baseURL: baseURL ?? self.baseURL, apiKey: "test-key-123"
            ),
            session: URLSession(configuration: config)
        )
    }

    private func fixtureData() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "sessions_list", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test("the request is an authenticated GET to /api/sessions with limit and offset")
    func requestShape() async throws {
        SessionsURLProtocol.responder = { _ in SessionsReply(body: try! fixtureData()) }

        _ = try await makeClient().listSessions(limit: 20, offset: 40)

        let request = try #require(SessionsURLProtocol.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.url?.absoluteString == "https://hermes.example.test/api/sessions?limit=20&offset=40")
        #expect(SessionsURLProtocol.requests.first?.httpMethod == "GET")
    }

    @Test("the default page is limit 50, offset 0")
    func defaultPage() async throws {
        SessionsURLProtocol.responder = { _ in SessionsReply(body: try! fixtureData()) }

        _ = try await makeClient().listSessions()

        let request = try #require(SessionsURLProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://hermes.example.test/api/sessions?limit=50&offset=0")
    }

    @Test("limit is clamped to 1...200 and offset to 0 or more")
    func clampsPagination() async throws {
        SessionsURLProtocol.responder = { _ in SessionsReply(body: try! fixtureData()) }
        let client = makeClient()

        _ = try await client.listSessions(limit: 0, offset: -5)
        _ = try await client.listSessions(limit: 999)

        let urls = SessionsURLProtocol.requests.compactMap { $0.url?.absoluteString }
        #expect(urls == [
            "https://hermes.example.test/api/sessions?limit=1&offset=0",
            "https://hermes.example.test/api/sessions?limit=200&offset=0",
        ])
    }

    @Test("a base URL with a trailing slash does not produce a double slash")
    func trailingSlashBaseURL() async throws {
        SessionsURLProtocol.responder = { _ in SessionsReply(body: try! fixtureData()) }
        let base = URL(string: "https://hermes.example.test/") ?? URL(filePath: "/")

        _ = try await makeClient(baseURL: base).listSessions()

        let request = try #require(SessionsURLProtocol.requests.first)
        #expect(request.url?.absoluteString.contains("//api") == false)
        #expect(request.url?.path == "/api/sessions")
    }

    @Test("the page decodes sessions, dates and has_more; unknown and absent fields are tolerated")
    func decodesPage() async throws {
        SessionsURLProtocol.responder = { _ in SessionsReply(body: try! fixtureData()) }

        let page = try await makeClient().listSessions()

        #expect(page.hasMore)
        #expect(page.sessions.count == 2)

        let first = page.sessions[0]
        #expect(first.id == "20261120_093000_a1b2c3")
        #expect(first.title == "Release notes draft")
        #expect(first.preview == "Can you draft the release notes?")
        #expect(first.messageCount == 4)
        #expect(first.startedAt == Date(timeIntervalSince1970: 1_795_157_400))
        #expect(first.lastActive == Date(timeIntervalSince1970: 1_795_161_000.5))
        #expect(first.pinned)
        #expect(!first.archived)

        let second = page.sessions[1]
        #expect(second.id == "20261119_180000_d4e5f6")
        #expect(second.title == nil)
        #expect(second.preview == nil)
        #expect(second.lastActive == nil)
        #expect(!second.pinned)
        #expect(second.archived)
    }

    @Test("an empty page is valid and has no more pages")
    func emptyPage() async throws {
        SessionsURLProtocol.responder = { _ in
            SessionsReply(body: Data(#"{"object":"list","data":[],"limit":50,"offset":0,"has_more":false}"#.utf8))
        }

        let page = try await makeClient().listSessions()

        #expect(page == SessionPage(sessions: [], hasMore: false))
    }

    @Test("a session without an id is an invalid response")
    func missingIdIsInvalid() async throws {
        SessionsURLProtocol.responder = { _ in
            SessionsReply(body: Data(#"{"data":[{"title":"x"}],"has_more":false}"#.utf8))
        }

        await #expect(throws: HermesAPIError.invalidResponse) {
            try await makeClient().listSessions()
        }
    }

    @Test("401 maps to unauthorized and 404 to notFound")
    func statusErrors() async throws {
        SessionsURLProtocol.responder = { _ in SessionsReply(status: 401) }
        await #expect(throws: HermesAPIError.unauthorized) {
            try await makeClient().listSessions()
        }

        SessionsURLProtocol.responder = { _ in SessionsReply(status: 404) }
        await #expect(throws: HermesAPIError.notFound) {
            try await makeClient().listSessions()
        }
    }

    @Test("a 503 from the session database maps to an HTTP error")
    func serviceUnavailable() async throws {
        SessionsURLProtocol.responder = { _ in SessionsReply(status: 503) }

        await #expect(throws: HermesAPIError.http(status: 503)) {
            try await makeClient().listSessions()
        }
    }

    @Test("a redirect (for example to an access gate) is an invalid response, not a list")
    func redirectIsInvalid() async throws {
        let gate = URL(string: "https://hermes.example.test/login") ?? URL(filePath: "/")
        SessionsURLProtocol.responder = { _ in
            SessionsReply(body: try! fixtureData(), responseURL: gate)
        }

        await #expect(throws: HermesAPIError.invalidResponse) {
            try await makeClient().listSessions()
        }
    }

    @Test("a timeout maps to timeout and a dropped connection to network")
    func transportErrors() async throws {
        SessionsURLProtocol.responder = { _ in SessionsReply(failure: URLError(.timedOut)) }
        await #expect(throws: HermesAPIError.timeout) {
            try await makeClient().listSessions()
        }

        SessionsURLProtocol.responder = { _ in SessionsReply(failure: URLError(.notConnectedToInternet)) }
        await #expect(throws: HermesAPIError.network) {
            try await makeClient().listSessions()
        }
    }
}
