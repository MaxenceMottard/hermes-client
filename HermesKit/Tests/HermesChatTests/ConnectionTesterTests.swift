import Foundation
import HermesAPI
import Testing

@testable import HermesChat

@Suite("ConnectionTester")
struct ConnectionTesterTests {
    @Test("a base URL that is not http or https is refused before any request")
    func invalidURL() async {
        #expect(await ConnectionTester.run(baseURLString: "ftp://hermes.example.test", apiKey: "key") == .invalidURL)
        #expect(await ConnectionTester.run(baseURLString: "hermes.example.test", apiKey: "key") == .invalidURL)
        #expect(await ConnectionTester.run(baseURLString: "", apiKey: "key") == .invalidURL)
    }

    @Test("an empty or blank API key is refused before any request")
    func missingKey() async {
        let outcome = await ConnectionTester.run(baseURLString: "https://hermes.example.test", apiKey: "   ")
        #expect(outcome == .missingKey)
    }

    @Test("typed API errors are kept as failures with their message")
    func typedErrors() {
        let cases: [HermesAPIError] = [.unauthorized, .notFound, .timeout, .network, .invalidResponse, .http(status: 500)]
        for error in cases {
            let outcome = ConnectionTester.outcome(for: error)
            #expect(outcome == .failed(error))
            #expect(outcome.message == error.errorDescription)
        }
    }

    @Test("URLError values map to typed errors, and cancellation is not a failure")
    func urlErrors() {
        #expect(ConnectionTester.outcome(for: URLError(.timedOut)) == .failed(.timeout))
        #expect(ConnectionTester.outcome(for: URLError(.notConnectedToInternet)) == .failed(.network))
        #expect(ConnectionTester.outcome(for: URLError(.cancelled)) == .cancelled)
        #expect(ConnectionTester.outcome(for: CancellationError()) == .cancelled)
        #expect(ConnectionTestOutcome.cancelled.message == nil)
    }

    @Test("success and failure messages are non-empty and do not contain the key")
    func messages() {
        let key = "secret-key-value"
        #expect(ConnectionTestOutcome.succeeded.message?.isEmpty == false)
        #expect(ConnectionTestOutcome.invalidURL.message?.isEmpty == false)
        #expect(ConnectionTestOutcome.missingKey.message?.isEmpty == false)
        for outcome in [ConnectionTestOutcome.succeeded, .invalidURL, .missingKey, .failed(.unauthorized)] {
            #expect(outcome.message?.contains(key) != true)
        }
    }
}
