import HermesChat
import SwiftUI

/// Connection settings: instance URL, model name, and API key. Shown on first launch and from the chat screen.
struct SettingsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var errorMessage: String?

    init(appState: AppState) {
        self.appState = appState
        _baseURL = State(initialValue: appState.settings?.baseURLString ?? "")
        _model = State(initialValue: appState.settings?.model ?? "hermes-agent")
        _apiKey = State(initialValue: appState.apiKey ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://hermes.example.test", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model name", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Instance")
                } footer: {
                    Text("The base URL of your Hermes instance and the model name it exposes.")
                }

                Section {
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("API key")
                } footer: {
                    Text("Stored on this device. The key gives shell access to the server: never share it.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let settings = ConnectionSettings(
            baseURLString: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard settings.isValid else {
            errorMessage = "Enter an http or https URL and a model name."
            return
        }
        do {
            try appState.save(
                settings: settings,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
        } catch {
            errorMessage = "The API key could not be saved on this device."
        }
    }
}
