import HermesAPI
import SwiftUI

/// The message composer floating over the bottom of a conversation: a rounded glass card with the
/// images waiting to be sent, the text field, and a row of actions (add, send or stop).
///
/// Both the local and the remote conversation screens use it. A screen that takes text only passes
/// no `onAdd`, which hides the add button.
struct ChatComposer: View {
    @Binding var draft: String
    /// Images waiting to be sent, shown above the text field.
    var pendingImages: [ImageAttachment] = []
    var onRemoveImage: (Int) -> Void = { _ in }
    /// Opens the add sheet. `nil` hides the add button.
    var onAdd: (() -> Void)?
    let isBusy: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !pendingImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, image in
                            PendingImageThumbnail(data: image.data) {
                                onRemoveImage(index)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 6)
                .padding(.horizontal, 6)
                .padding(.top, pendingImages.isEmpty ? 6 : 0)

            HStack(spacing: 10) {
                if let onAdd {
                    Button("Add images", systemImage: "plus", action: onAdd)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .disabled(isBusy)
                }

                Spacer(minLength: 0)

                if isBusy {
                    Button("Stop", systemImage: "stop.fill", action: onStop)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                } else {
                    Button("Send", systemImage: "arrow.up", action: onSend)
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .disabled(!canSend)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// An image waiting in the composer, with a round button in its corner that removes it.
private struct PendingImageThumbnail: View {
    let data: Data
    let onRemove: () -> Void

    var body: some View {
        (ImageAttachmentLoader.thumbnail(for: data) ?? Image(systemName: "photo"))
            .resizable()
            .scaledToFill()
            .frame(width: 80, height: 80)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(.white, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove image")
                .padding(5)
            }
    }
}

/// A short status line (progress, error, notice) floating above the composer, readable over the
/// messages that scroll beneath it.
struct ComposerStatus<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 6) {
            content
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }
}
