/// An event emitted by the SSE parser.
public enum SSEEvent: Sendable, Equatable {
    /// Payload of a `data:` line (without the prefix or the leading space).
    case data(String)
    /// The `data: [DONE]` sentinel: end of stream.
    case done
}

/// Synchronous SSE parser, independent of the byte source.
///
/// Accumulates bytes up to `\n` (or `\r\n`), so a line can be split anywhere
/// between two `feed` calls. Each `data:` line produces an event immediately;
/// empty lines, comments (`: ...`) and other fields (`event:`, `id:`, `retry:`) are ignored.
public struct SSEParser: Sendable {
    private var buffer: [UInt8] = []
    private var isFinished = false

    public init() {}

    /// `true` once `data: [DONE]` has been seen: any following bytes are ignored.
    public var hasFinished: Bool { isFinished }

    /// Consumes bytes and returns the complete events they close.
    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [SSEEvent] {
        var events: [SSEEvent] = []
        for byte in bytes {
            guard !isFinished else { break }
            if byte == UInt8(ascii: "\n") {
                if let event = parseLine(buffer) {
                    events.append(event)
                    if event == .done { isFinished = true }
                }
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(byte)
            }
        }
        return events
    }

    /// Call at the end of the source: processes a last line that was not terminated by `\n`.
    public mutating func finish() -> [SSEEvent] {
        guard !isFinished, !buffer.isEmpty else { return [] }
        let event = parseLine(buffer)
        buffer.removeAll()
        if event == .done { isFinished = true }
        return event.map { [$0] } ?? []
    }

    private func parseLine(_ raw: [UInt8]) -> SSEEvent? {
        var line = raw[...]
        if line.last == UInt8(ascii: "\r") {
            line = line.dropLast()
        }
        // Empty line (event separator) or comment.
        guard let first = line.first, first != UInt8(ascii: ":") else { return nil }

        let prefix = Array("data:".utf8)
        guard line.starts(with: prefix) else { return nil }

        var value = line.dropFirst(prefix.count)
        if value.first == UInt8(ascii: " ") {
            value = value.dropFirst()
        }
        guard !value.isEmpty else { return nil }

        let payload = String(decoding: value, as: UTF8.self)
        return payload == "[DONE]" ? .done : .data(payload)
    }
}

/// Turns a byte sequence (e.g. `URLSession.AsyncBytes`) into a stream of SSE events.
///
/// The stream ends after `data: [DONE]`, at the end of the source, or with an error if the source fails.
/// Cancelling the consuming task cancels the byte reading.
public func sseEvents<Bytes>(_ bytes: Bytes) -> AsyncThrowingStream<SSEEvent, any Error>
where Bytes: AsyncSequence & Sendable, Bytes.Element == UInt8 {
    AsyncThrowingStream { continuation in
        let task = Task {
            var parser = SSEParser()
            do {
                for try await byte in bytes {
                    for event in parser.feed(CollectionOfOne(byte)) {
                        continuation.yield(event)
                    }
                    if parser.hasFinished {
                        continuation.finish()
                        return
                    }
                }
                for event in parser.finish() {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
