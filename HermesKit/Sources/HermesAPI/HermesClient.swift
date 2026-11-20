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
                        try Self.validate(response, requestURL: request.url)
                        try await Self.forEachDelta(in: bytes) { continuation.yield($0) }
                    #else
                        // Linux (tests only): URLSession.bytes is unavailable, so the body is buffered.
                        let (data, response) = try await session.data(for: request)
                        try Self.validate(response, requestURL: request.url)
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

    /// Sends one text message to a session stored on the instance and streams the reply events, in order.
    ///
    /// `POST {baseURL}/api/sessions/{id}/chat/stream`. The stream finishes on `done` or at the end of the
    /// response. Cancelling the consuming task, or leaving the loop, cancels the request. The request is
    /// never retried automatically.
    public func streamSessionChat(sessionID: String, message: String) -> AsyncThrowingStream<SessionChatEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // The id goes into the path as is: it must be a single segment.
                    guard !sessionID.isEmpty, !sessionID.contains("/") else {
                        throw HermesAPIError.invalidResponse
                    }
                    var request = makeRequest(
                        method: "POST",
                        path: HermesAPIPaths.sessionChatStream(sessionID),
                        accept: "text/event-stream"
                    )
                    request.httpBody = try JSONEncoder().encode(SessionChatRequest(message: message))
                    #if canImport(Darwin)
                        let (bytes, response) = try await session.bytes(for: request)
                        try Self.validate(response, requestURL: request.url)
                        try await Self.forEachSessionEvent(in: bytes) { continuation.yield($0) }
                    #else
                        // Linux (tests only): URLSession.bytes is unavailable, so the body is buffered.
                        let (data, response) = try await session.data(for: request)
                        try Self.validate(response, requestURL: request.url)
                        let bytes = AsyncThrowingStream<UInt8, any Error> { source in
                            for byte in data {
                                source.yield(byte)
                            }
                            source.finish()
                        }
                        try await Self.forEachSessionEvent(in: bytes) { continuation.yield($0) }
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

    /// Parses the named events of a session chat stream and emits each one that a transcript shows,
    /// until `done`.
    private static func forEachSessionEvent<Bytes: AsyncSequence>(
        in bytes: Bytes,
        _ emit: (SessionChatEvent) -> Void
    ) async throws where Bytes.Element == UInt8 {
        var parser = SessionEventParser()
        for try await byte in bytes {
            for frame in parser.feed(CollectionOfOne(byte)) {
                if emitSessionEvent(frame, emit) { return }
            }
        }
        for frame in parser.finish() {
            if emitSessionEvent(frame, emit) { return }
        }
    }

    /// Returns `true` once the stream is complete (`done`).
    private static func emitSessionEvent(_ frame: SessionEventFrame, _ emit: (SessionChatEvent) -> Void) -> Bool {
        guard let event = SessionChatEvent(frame) else { return false }
        if event == .finished {
            return true
        }
        emit(event)
        return false
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

    /// Sends the conversation without streaming and returns the text of the first choice.
    public func chat(model: String, messages: [ChatMessage]) async throws -> String {
        do {
            let request = try makeRequest(model: model, messages: messages, stream: false)
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, requestURL: request.url)

            let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
            guard let content = completion.choices.first?.message.content else {
                throw HermesAPIError.invalidResponse
            }
            return content
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw HermesAPIError.from(error)
        }
    }

    /// Checks that the instance answers at `HermesAPIPaths.health`.
    ///
    /// Succeeds only for a 2xx response that was not redirected and has a JSON object body. A redirect
    /// (for example an access gate sending the request to `/login`) and a non-JSON body are errors.
    /// Throws `HermesAPIError`; cancellation throws `CancellationError`.
    public func healthCheck() async throws {
        do {
            let request = makeRequest(method: "GET", path: HermesAPIPaths.health, accept: "application/json")
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, requestURL: request.url)
            guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                throw HermesAPIError.invalidResponse
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw HermesAPIError.from(error)
        }
    }

    /// Lists the model IDs from `GET {baseURL}/v1/models`.
    ///
    /// A failed listing is not an error: any HTTP, network, timeout or contract failure returns
    /// `.fallback` with the reason, so that the user can type a model name by hand.
    /// Only cancellation throws (`CancellationError`).
    public func listModels() async throws -> ModelListResult {
        do {
            let request = makeRequest(method: "GET", path: HermesAPIPaths.models, accept: "application/json")
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, requestURL: request.url)
            let list = try JSONDecoder().decode(ModelList.self, from: data)
            let ids = list.data.map(\.id)
            guard !ids.isEmpty else {
                return .fallback(.invalidResponse)
            }
            return .models(ids)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return .fallback(HermesAPIError.from(error))
        }
    }

    /// Fetches one page of sessions from `GET {baseURL}/api/sessions`, most recently active first.
    ///
    /// `limit` is clamped to the 1...200 range the instance accepts. Unlike `listModels()`, a failure
    /// is thrown: the conversation list has no fallback. Cancellation throws `CancellationError`.
    public func listSessions(limit: Int = 50, offset: Int = 0) async throws -> SessionPage {
        do {
            let query = [
                URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))),
                URLQueryItem(name: "offset", value: String(max(offset, 0))),
            ]
            let request = makeRequest(
                method: "GET", path: HermesAPIPaths.sessions, accept: "application/json", query: query
            )
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, requestURL: request.url)
            let body = try JSONDecoder().decode(SessionListBody.self, from: data)
            return SessionPage(sessions: body.data, hasMore: body.hasMore)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw HermesAPIError.from(error)
        }
    }

    /// Fetches one page of a session's messages, from `GET {baseURL}/api/sessions/{id}/messages`.
    ///
    /// Paging starts from the newest message: `offset` 0 is the last message, and each larger offset goes back
    /// in time. The page itself is in chronological order, oldest first. `limit` is clamped to 1...500, the
    /// maximum the instance accepts; `offset` to 0 or more. `hasMore` is true when the page was full. Failures are thrown, as for `listSessions(limit:offset:)`.
    public func listSessionMessages(sessionID: String, limit: Int = 200, offset: Int = 0) async throws -> SessionMessagesPage {
        do {
            // The id goes into the path as is: it must be a single segment.
            guard !sessionID.isEmpty, !sessionID.contains("/") else {
                throw HermesAPIError.invalidResponse
            }
            let pageLimit = min(max(limit, 1), 500)
            let query = [
                URLQueryItem(name: "limit", value: String(pageLimit)),
                URLQueryItem(name: "offset", value: String(max(offset, 0))),
                URLQueryItem(name: "order", value: "latest"),
            ]
            let request = makeRequest(
                method: "GET",
                path: HermesAPIPaths.sessionMessages(sessionID),
                accept: "application/json",
                query: query
            )
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, requestURL: request.url)
            let body = try JSONDecoder().decode(SessionMessagesBody.self, from: data)
            return SessionMessagesPage(
                sessionID: sessionID,
                messages: body.data,
                hasMore: body.returned == pageLimit
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw HermesAPIError.from(error)
        }
    }

    /// Copies a session into a new session owned by the API, from `POST {baseURL}/api/sessions/{id}/fork`,
    /// and returns the new session.
    ///
    /// The instance copies every message, gives the copy a title derived from the original, and ends
    /// the original as `branched`. Use it to continue a session the API may not write to (see
    /// `RemoteSession.acceptsAPIMessages`). The request is never retried automatically.
    public func forkSession(sessionID: String) async throws -> RemoteSession {
        do {
            // The id goes into the path as is: it must be a single segment.
            guard !sessionID.isEmpty, !sessionID.contains("/") else {
                throw HermesAPIError.invalidResponse
            }
            var request = makeRequest(
                method: "POST", path: HermesAPIPaths.sessionFork(sessionID), accept: "application/json"
            )
            request.httpBody = Data("{}".utf8)
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, requestURL: request.url)
            return try JSONDecoder().decode(SessionForkBody.self, from: data).session
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw HermesAPIError.from(error)
        }
    }

    /// Builds `POST {baseURL}/v1/chat/completions`. Internal for tests.
    func makeRequest(model: String, messages: [ChatMessage], stream: Bool) throws -> URLRequest {
        var request = makeRequest(
            method: "POST",
            path: HermesAPIPaths.chatCompletions,
            accept: stream ? "text/event-stream" : "application/json"
        )
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: model, messages: messages, stream: stream)
        )
        return request
    }

    /// Builds an authenticated request to `{baseURL}{path}`, with the Bearer header and the client timeout.
    private func makeRequest(
        method: String, path: String, accept: String, query: [URLQueryItem] = []
    ) -> URLRequest {
        let relativePath = String(path.drop(while: { $0 == "/" }))
        var url = configuration.baseURL.appending(path: relativePath)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = configuration.timeout
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Rejects non-2xx statuses, and any response whose final URL differs from the request URL
    /// (a redirect, for example to an access gate's `/login` page), so that it never counts as a success.
    private static func validate(_ response: URLResponse, requestURL: URL?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIError.invalidResponse
        }
        if let error = HermesAPIError.from(status: http.statusCode) {
            throw error
        }
        guard http.url == requestURL else {
            throw HermesAPIError.invalidResponse
        }
    }
}
