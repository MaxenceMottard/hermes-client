import Foundation
import Testing

@testable import HermesChat

@Suite("Connection settings")
struct ConnectionSettingsTests {
    @Test("an http or https URL with a host is accepted")
    func acceptsAbsoluteURLs() {
        #expect(ConnectionSettings.parseBaseURL("https://hermes.example.test") != nil)
        #expect(ConnectionSettings.parseBaseURL("  http://192.168.1.10:8642  ") != nil)
    }

    @Test("empty, relative, non-http and hostless URLs are rejected")
    func rejectsInvalidURLs() {
        #expect(ConnectionSettings.parseBaseURL("") == nil)
        #expect(ConnectionSettings.parseBaseURL("hermes.example.test") == nil)
        #expect(ConnectionSettings.parseBaseURL("ftp://hermes.example.test") == nil)
        #expect(ConnectionSettings.parseBaseURL("https://") == nil)
    }

    @Test("settings are valid only with a URL and a non-empty model")
    func validity() {
        #expect(ConnectionSettings(baseURLString: "https://hermes.example.test", model: "m").isValid)
        #expect(!ConnectionSettings(baseURLString: "https://hermes.example.test", model: "  ").isValid)
        #expect(!ConnectionSettings(baseURLString: "nope", model: "m").isValid)
    }

    @Test("the storage round-trips settings and returns nil when empty")
    func storageRoundTrip() {
        let suite = "test.connection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = UserDefaultsSettingsStorage(defaults: defaults)

        #expect(storage.load() == nil)
        let settings = ConnectionSettings(baseURLString: "https://hermes.example.test", model: "agent")
        storage.save(settings)
        #expect(storage.load() == settings)
    }
}
