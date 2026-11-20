import Foundation
import Testing

@testable import HermesChat

@MainActor
@Suite("Last used model")
struct LastModelStorageTests {
    @Test("UserDefaults storage keeps the model and provider across instances and ignores blank values")
    func userDefaultsRoundTrip() throws {
        let suite = "LastModelStorageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(UserDefaultsLastModelStorage(defaults: defaults).load() == nil)

        UserDefaultsLastModelStorage(defaults: defaults).save(ModelChoice(model: "opus", provider: "anthropic"))
        #expect(
            UserDefaultsLastModelStorage(defaults: defaults).load() == ModelChoice(model: "opus", provider: "anthropic"))

        UserDefaultsLastModelStorage(defaults: defaults).save(ModelChoice(model: "hermes-agent"))
        #expect(UserDefaultsLastModelStorage(defaults: defaults).load() == ModelChoice(model: "hermes-agent"))

        defaults.set("   ", forKey: UserDefaultsLastModelStorage.modelKey)
        #expect(UserDefaultsLastModelStorage(defaults: defaults).load() == nil)
    }

    @Test("the display name shows the provider before the model")
    func displayName() {
        #expect(ModelChoice(model: "opus", provider: "anthropic").displayName == "anthropic · opus")
        #expect(ModelChoice(model: "hermes-agent").displayName == "hermes-agent")
    }
}
