import HermesAPI
import HermesChat
import PhotosUI
import SwiftUI

/// Conversation screen: message list, composer, and Send / Stop.
struct ChatView: View {
    let session: ChatSession
    @State private var draft = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingImages: [ImageAttachment] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                        MessageRow(message: message)
                    }
                }
                .padding()
            }

            if session.phase == .sending {
                ProgressView()
                    .padding(.bottom, 4)
            }

            if let message = failureMessage {
                VStack(spacing: 6) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    if session.canRetry {
                        Button("Retry") {
                            Task { await session.retry() }
                        }
                    }
                }
                .padding(.horizontal)
            }

            if !pendingImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, image in
                            AttachmentThumbnail(data: image.data) {
                                pendingImages.remove(at: index)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, ChatSession.maxImagesPerMessage - pendingImages.count),
                    matching: .images
                ) {
                    Label("Attach image", systemImage: "photo")
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .disabled(session.isBusy || pendingImages.count >= ChatSession.maxImagesPerMessage)

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 5)

                if session.isBusy {
                    Button("Stop", systemImage: "stop.circle.fill") {
                        session.stop()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill") {
                        let text = draft
                        let images = pendingImages
                        draft = ""
                        pendingImages = []
                        Task { await session.send(text, images: images) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .disabled(!canSend)
                }
            }
            .padding()
        }
        .onChange(of: pickerItems) { _, items in
            Task { await loadPicked(items) }
        }
    }
}

private extension ChatView {
    var canSend: Bool {
        !pendingImages.isEmpty || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
