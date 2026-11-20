import HermesChat
import SwiftUI

/// Read-only transcript of a session stored on the Hermes instance, shown in a sheet.
struct RemoteTranscriptView: View {
    let transcript: RemoteTranscript

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(transcript.lines) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.role == "user" ? "You" : "Hermes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(line.text)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                footer
            }
            .navigationTitle(transcript.title ?? "Session")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await transcript.load()
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch transcript.state {
        case .loading:
            ProgressView()
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await transcript.load() }
                }
            }
        case .idle, .loaded:
            if transcript.hasMore {
                Button("Load more") {
                    Task { await transcript.loadMore() }
                }
            }
        }
    }
}
