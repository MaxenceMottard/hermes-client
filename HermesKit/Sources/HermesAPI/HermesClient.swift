import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Explicit client configuration: base URL and API key, provided by the caller.
/// No default value and no singleton. The key never appears in descriptions.
public struct HermesClientConfiguration: Sendable {
    public let baseURL: URL
    public let apiKey: String
    /// Request timeout. Large, because an agent request can run for ~30 minutes.
    public let timeout: TimeInterval

    public init(baseURL: URL, apiKey: String, timeout: TimeInterval = 30 * 60) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
    }
}

extension HermesClientConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "HermesClientConfiguration(baseURL: \(baseURL.absoluteString), apiKey: <redacted>)"
    }

    public var debugDescription: String { description }
}

/// Client for a Hermes instance (OpenAI-compatible API).
///
/// POST requests are never retried automatically.
public struct HermesClient: Sendable {
    public let configuration: HermesClientConfiguration
    private let session: URLSession

    public init(configuration: HermesClientConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Sends the conversation in streaming mode and emits the non-empty `delta.content` values, in order.
    ///
    /// The stream finishes on `data: [DONE]` (or at the end of the response). Cancelling the
    /// consuming task, or leaving the `for try await` loop, cancels the network request.
    public func streamChat(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(model: model, messages: messages, stream: true)
                    #if canImport(Darwin)
                        let (bytes, response) = try await session.bytes(for: request)
                        try Self.validate(response)
                        try await Self.forEachDelta(in: bytes) { continuation.yield($0) }
                    #else
                        // Linux (tests only): URLSession.bytes is unavailable, so the body is buffered.
                        let (data, response) = try await session.data(for: request)
                        try Self.validate(response)
                        let bytes = AsyncThrowingStream<UInt8, any Error> { source in
                            for byte in data {
                                source.yield(byte)
                            }
                            source.finish()
                        }
                        try await Self.forEachDelta(in: bytes) { continuation.yield($0) }
                    #endif
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: HermesAPIError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Parses the byte stream and calls `emit` for each non-empty `delta.content`, until `[DONE]`.
    private static func forEachDelta<Bytes: AsyncSequence>(
        in bytes: Bytes,
        _ emit: (String) -> Void
    ) async throws where Bytes.Element == UInt8 {
        var parser = SSEParser()
        for try await byte in bytes {
            for event in parser.feed(CollectionOfOne(byte)) {
                if try handle(event, emit) { return }
            }
        }
        for event in parser.finish() {
            if try handle(event, emit) { return }
        }
    }

    /// Returns `true` once the stream is complete (`[DONE]`).
    private static func handle(_ event: SSEEvent, _ emit: (String) -> Void) throws -> Bool {
        switch event {
        case .done:
            return true
        case .data(let payload):
            let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(payload.utf8))
            if let delta = chunk.contentDelta, !delta.isEmpty {
                emit(delta)
            }
            return false
        }
    }

    /// Builds `POST {baseURL}/v1/chat/completions`. Internal for tests.
    func makeRequest(model: String, messages: [ChatMessage], stream: Bool) throws -> URLRequest {
        let relativePath = String(HermesAPIPaths.chatCompletions.drop(while: { $0 == "/" }))
        var request = URLRequest(url: configuration.baseURL.appending(path: relativePath))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: model, messages: messages, stream: stream)
        )
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIError.invalidResponse
        }
        if let error = HermesAPIError.from(status: http.statusCode) {
            throw error
        }
    }
}
