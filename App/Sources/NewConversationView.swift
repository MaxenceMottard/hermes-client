import HermesAPI
import HermesChat
import SwiftUI

/// Shown before a new conversation starts: pick the model it will talk to.
/// Lists the instance models with the last used one preselected, or falls back to a text field.
struct NewConversationView: View {
    /// Called with the chosen model when the user taps Start.
    let onStart: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picker: ModelPicker

    init(catalog: (any ModelCatalog)?, preferredModel: String, onStart: @escaping (String) -> Void) {
        self.onStart = onStart
        _picker = State(initialValue: ModelPicker(catalog: catalog, preferred: preferredModel))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Choose a model")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start", action: start)
                            .disabled(picker.chosenModel == nil)
                    }
                }
        }
        .task { await picker.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch picker.state {
        case .loading:
            ProgressView("Loading models…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .list(let models):
            List(models, id: \.self) { model in
                Button {
                    picker.selection = model
                } label: {
                    HStack {
                        Text(model)
                            .foregroundStyle(.primary)
                        Spacer()
                        if model == picker.selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model == picker.selection ? .isSelected : [])
            }
        case .manual(let reason):
            Form {
                Section {
                    TextField("Model name", text: $picker.selection)
                        .autocorrectionDisabled()
                        .onSubmit(start)
                } footer: {
                    Text(manualFooter(reason))
                }
            }
        }
    }

    private func manualFooter(_ reason: HermesAPIError?) -> String {
        let explanation = "Type the name of the model to use."
        guard let description = reason?.errorDescription else { return explanation }
        return "The model list is unavailable: \(description) \(explanation)"
    }

    private func start() {
        guard let model = picker.chosenModel else { return }
        onStart(model)
        dismiss()
    }
}
