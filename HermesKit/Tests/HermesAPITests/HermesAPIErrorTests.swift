import Foundation
import Testing

@testable import HermesAPI

@Suite("Typed HermesAPIError")
struct HermesAPIErrorTests {
    @Test("401 maps to unauthorized, 404 to notFound, other errors to http(status:)")
    func statusMapping() {
        #expect(HermesAPIError.from(status: 401) == .unauthorized)
        #expect(HermesAPIError.from(status: 404) == .notFound)
        #expect(HermesAPIError.from(status: 500) == .http(status: 500))
        #expect(HermesAPIError.from(status: 429) == .http(status: 429))
    }

    @Test("2xx statuses do not produce an error")
    func successStatusesAreNotErrors() {
        #expect(HermesAPIError.from(status: 200) == nil)
        #expect(HermesAPIError.from(status: 204) == nil)
        #expect(HermesAPIError.from(status: 299) == nil)
    }

    @Test("URLError.timedOut maps to timeout")
    func timeoutMapping() {
        #expect(HermesAPIError.from(URLError(.timedOut)) == .timeout)
    }

    @Test("other URLErrors map to network")
    func networkMapping() {
        #expect(HermesAPIError.from(URLError(.notConnectedToInternet)) == .network)
        #expect(HermesAPIError.from(URLError(.cannotConnectToHost)) == .network)
    }

    @Test("a decoding error maps to invalidResponse")
    func decodingMapping() {
        do {
            _ = try JSONDecoder().decode([String: Int].self, from: Data("not json".utf8))
            Issue.record("invalid decoding should have failed")
        } catch {
            #expect(HermesAPIError.from(error) == .invalidResponse)
        }
    }

    @Test("a HermesAPIError is passed through unchanged")
    func passThrough() {
        #expect(HermesAPIError.from(HermesAPIError.unauthorized) == .unauthorized)
    }

    @Test("each message is readable English and contains no key or header")
    func messagesAreSafe() throws {
        let all: [HermesAPIError] = [
            .unauthorized, .notFound, .timeout, .network, .invalidResponse, .http(status: 503),
        ]
        for error in all {
            let message = try #require(error.errorDescription)
            #expect(!message.isEmpty)
            let lowered = message.lowercased()
            #expect(!lowered.contains("bearer"))
            #expect(!lowered.contains("authorization"))
            #expect(!lowered.contains("sk-"))
        }
        #expect(HermesAPIError.http(status: 503).errorDescription?.contains("503") == true)
    }
}
