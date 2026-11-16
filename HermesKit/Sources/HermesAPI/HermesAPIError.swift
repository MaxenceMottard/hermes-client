import Foundation

/// Single error type surfaced by the Hermes client. Messages are meant for the UI
/// and never contain the API key or any header.
public enum HermesAPIError: Error, Sendable, Equatable {
    /// 401: key missing or rejected.
    case unauthorized
    /// 404: endpoint not found (the base URL is probably wrong).
    case notFound
    /// The request exceeded its timeout.
    case timeout
    /// Connection failed (offline, DNS, TLS, dropped connection).
    case network
    /// A response was received but does not match the expected contract.
    case invalidResponse
    /// Any other HTTP error status.
    case http(status: Int)
}

extension HermesAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "API key rejected (401). Check the key in the settings."
        case .notFound:
            "Endpoint not found (404). Check the instance URL."
        case .timeout:
            "The request timed out. The agent may be busy, try again."
        case .network:
            "Cannot connect. Check your network and the instance URL."
        case .invalidResponse:
            "The instance returned an invalid response."
        case .http(let status):
            "Server error (HTTP \(status))."
        }
    }
}

extension HermesAPIError {
    /// Maps an HTTP status code. Returns `nil` for a 2xx status.
    public static func from(status: Int) -> HermesAPIError? {
        switch status {
        case 200..<300: nil
        case 401: .unauthorized
        case 404: .notFound
        default: .http(status: status)
        }
    }

    /// Maps a transport or decoding error to the single error type.
    public static func from(_ error: any Error) -> HermesAPIError {
        if let apiError = error as? HermesAPIError {
            return apiError
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? .timeout : .network
        }
        if error is DecodingError {
            return .invalidResponse
        }
        return .network
    }
}
