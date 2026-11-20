import Foundation
import Testing

@testable import HermesAPI

@Suite("OpenAI-compatible Codable models")
struct HermesAPIModelsTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("the request encodes exactly model, messages and stream")
    func requestEncodesExactKeys() throws {
        let request = ChatRequest(
            model: "hermes-test-model",
            messages: [ChatMessage(role: "user", content: "Hi")],
            stream: false
        )
        let object = try jsonObject(JSONEncoder().encode(request))

        #expect(Set(object.keys) == ["model", "messages", "stream"])
        #expect(object["model"] as? String == "hermes-test-model")
        #expect(object["stream"] as? Bool == false)
        let messages = try #require(object["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "Hi"]])
    }

    @Test("stream: true is encoded as is")
    func requestStreamTrue() throws {
        let request = ChatRequest(model: "m", messages: [], stream: true)
        let object = try jsonObject(JSONEncoder().encode(request))
        #expect(object["stream"] as? Bool == true)
    }

    @Test("the provider is encoded only when set")
    func requestProvider() throws {
        let withProvider = try jsonObject(
            JSONEncoder().encode(ChatRequest(model: "m", provider: "anthropic", messages: [], stream: true)))
        #expect(withProvider["provider"] as? String == "anthropic")

        let without = try jsonObject(JSONEncoder().encode(ChatRequest(model: "m", messages: [], stream: true)))
        #expect(without["provider"] == nil)
    }

    @Test("a non-streamed response decodes and re-encodes without loss")
    func completionRoundTrip() throws {
        let decoded = try JSONDecoder().decode(ChatCompletion.self, from: fixture("chat_completion"))

        #expect(decoded.id == "chatcmpl-test-001")
        #expect(decoded.model == "hermes-test-model")
        #expect(decoded.choices.count == 1)
        let first = decoded.choices[0].message
        #expect(first == ChatMessage(role: "assistant", content: "Hello, how can I help?"))
        #expect(decoded.choices[0].finishReason == "stop")

        let reencoded = try JSONEncoder().encode(decoded)
        #expect(try JSONDecoder().decode(ChatCompletion.self, from: reencoded) == decoded)
    }

    @Test("an SSE chunk decodes and exposes the content delta")
    func chunkDecodes() throws {
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: fixture("chat_chunk"))

        #expect(chunk.contentDelta == "Hello")
        #expect(chunk.choices[0].delta.role == "assistant")
        #expect(chunk.choices[0].finishReason == nil)

        let reencoded = try JSONEncoder().encode(chunk)
        #expect(try JSONDecoder().decode(ChatChunk.self, from: reencoded) == chunk)
    }

    @Test("a chunk without content (role only, end of stream) has a nil delta")
    func chunkWithoutContent() throws {
        let json = Data(#"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#.utf8)
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: json)
        #expect(chunk.contentDelta == nil)
        #expect(chunk.choices[0].finishReason == "stop")
    }

    @Test("unknown fields do not break decoding")
    func unknownFieldsIgnored() throws {
        let json = Data(#"{"model":"m","choices":[],"future_field":{"a":[1,2]},"x":null}"#.utf8)
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: json)
        #expect(chunk.choices.isEmpty)
        #expect(chunk.contentDelta == nil)
    }
}
