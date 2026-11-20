import Foundation
import HermesAPI

/// Result of the "Test connection" button in the settings screen.
public enum ConnectionTestOutcome: Sendable, Equatable {
    /// The instance answered the health check.
    case succeeded
    /// The base URL is not an absolute http or https URL with a host.
    case invalidURL
    /// The API key field is empty.
    case missingKey
    /// The health check failed with a typed error.
    case failed(HermesAPIError)
    /// The check was cancelled (for example, the settings screen was dismissed). Nothing to show.
    case cancelled

    /// Text shown under the button, or `nil` when nothing should be shown.
    public var message: String? {
        switch self {
        case .succeeded:
            "Connection OK. The instance answered the health check."
        case .invalidURL:
            "Enter an http or https URL with a host."
        case .missingKey:
            "Enter the API key."
        case .failed(let error):
            error.errorDescription
        case .cancelled:
            nil
        }
    }
}

/// Runs the connection test from the values typed in the settings screen, without saving them.
public enum ConnectionTester {
    /// Builds a client from the typed URL and key, then runs `HermesClient.healthCheck()`.
    public static func run(baseURLString: String, apiKey: String) async -> ConnectionTestOutcome {
        guard let baseURL = ConnectionSettings.parseBaseURL(baseURLString) else {
            return .invalidURL
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingKey
        }
        let client = HermesClient(configuration: HermesClientConfiguration(baseURL: baseURL, apiKey: apiKey))
        do {
            try await client.healthCheck()
            return .succeeded
        } catch {
            return outcome(for: error)
        }
    }

    /// Maps an error thrown by a health check to an outcome. Cancellation is kept apart from failures.
    static func outcome(for error: any Error) -> ConnectionTestOutcome {
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }
        return .failed(HermesAPIError.from(error))
    }
}
