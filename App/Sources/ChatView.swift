import HermesAPI
import HermesChat
import PhotosUI
import SwiftUI

/// Conversation screen: the message list, with the floating composer over its bottom.
struct ChatView: View {
    let session: ChatSession
    @State private var draft = ""
    @State private var isPickingPhotos = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingImages: [ImageAttachment] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                    MessageRow(message: message)
                }
            }
            .padding()
        }
        // The messages scroll beneath the composer.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if session.phase == .sending {
                    ComposerStatus {
                        ProgressView()
                    }
                }

                if let message = failureMessage {
                    ComposerStatus {
                        Text(message)
                            .foregroundStyle(.red)
                        if session.canRetry {
                            Button("Retry") {
                                Task { await session.retry() }
                            }
                        }
                    }
                }

                ChatComposer(
                    draft: $draft,
                    pendingImages: pendingImages,
                    onRemoveImage: { pendingImages.remove(at: $0) },
                    onAdd: { isPickingPhotos = true },
                    canAdd: pendingImages.count < ChatSession.maxImagesPerMessage,
                    isBusy: session.isBusy,
                    canSend: canSend,
                    onSend: send,
                    onStop: { session.stop() }
                )
            }
        }
        .photosPicker(
            isPresented: $isPickingPhotos,
            selection: $pickerItems,
            maxSelectionCount: max(1, ChatSession.maxImagesPerMessage - pendingImages.count),
            matching: .images
        )
        .onChange(of: pickerItems) { _, items in
            Task { await loadPicked(items) }
        }
    }
}

private extension ChatView {
    var canSend: Bool {
        !pendingImages.isEmpty || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() {
        let text = draft
        let images = pendingImages
        draft = ""
        pendingImages = []
        Task { await session.send(text, images: images) }
    }

    /// Converts the picked photos and adds them to the composer, up to the per-message limit.
    func loadPicked(_ items: [PhotosPickerItem]) async {
        for item in items where pendingImages.count < ChatSession.maxImagesPerMessage {
            if let attachment = await ImageAttachmentLoader.attachment(from: item) {
                pendingImages.append(attachment)
            }
        }
        pickerItems = []
    }

    var failureMessage: String? {
        switch session.phase {
        case .failed(let error):
            error.errorDescription ?? "Unknown error"
        case .emptyReply:
            "The agent sent an empty reply."
        case .idle, .sending, .streaming:
            nil
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                if !message.images.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                                AttachmentThumbnail(data: image.data)
                            }
                        }
                    }
                }
                if message.role == "user" {
                    if !message.content.isEmpty {
                        Text(message.content)
                    }
                } else {
                    MarkdownView(source: message.content)
                }
            }
            .padding(10)
                .background(
                    message.role == "user" ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            if message.role != "user" { Spacer(minLength: 40) }
        }
    }
}
