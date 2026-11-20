import HermesAPI
import HermesChat
import SwiftUI

/// Shown before a new conversation starts: pick the model it will talk to.
/// Lists the models grouped by provider, as the dashboard does, with the last used one preselected.
/// Falls back to text fields when the instance gives no list.
struct NewConversationView: View {
    /// Called with the chosen model when the user taps Start.
    let onStart: (ModelChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picker: ModelPicker

    init(
        catalog: (any ModelCatalog)?,
        preferred: ModelChoice,
        defaultChoice: ModelChoice,
        onStart: @escaping (ModelChoice) -> Void
    ) {
        self.onStart = onStart
        _picker = State(
            initialValue: ModelPicker(catalog: catalog, preferred: preferred, defaultChoice: defaultChoice))
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
                            .disabled(picker.chosen == nil)
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
        case .sections(let sections):
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.choices, id: \.self) { choice in
                            row(choice)
                        }
                    }
                }
            }
        case .manual(let reason):
            Form {
                Section {
                    TextField("Model name", text: $picker.selection.model)
                        .autocorrectionDisabled()
                        .onSubmit(start)
                    TextField("Provider (optional)", text: providerText)
                        .autocorrectionDisabled()
                        .onSubmit(start)
                } footer: {
                    Text(manualFooter(reason))
                }
            }
        }
    }

    private func row(_ choice: ModelChoice) -> some View {
        Button {
            picker.selection = choice
        } label: {
            HStack {
                Text(choice.model)
                    .foregroundStyle(.primary)
                Spacer()
                if choice == picker.selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == picker.selection ? .isSelected : [])
    }

    /// The provider text field edits `selection.provider`; an empty field means no provider.
    private var providerText: Binding<String> {
        Binding(
            get: { picker.selection.provider ?? "" },
            set: { picker.selection.provider = $0.isEmpty ? nil : $0 }
        )
    }

    private func manualFooter(_ reason: HermesAPIError?) -> String {
        let explanation = "Type the name of the model to use, and its provider (for example anthropic) to use a provider model."
        guard let description = reason?.errorDescription else { return explanation }
        return "The model list is unavailable: \(description) \(explanation)"
    }

    private func start() {
        guard let choice = picker.chosen else { return }
        onStart(choice)
        dismiss()
    }
}
