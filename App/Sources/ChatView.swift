import HermesAPI
import HermesChat
import PhotosUI
import SwiftUI

/// Conversation screen: the message list, with the floating composer over its bottom.
struct ChatView: View {
    let session: ChatSession
    @State private var draft = ""
    @State private var isAddingImages = false
    /// The photos picked in the add sheet. `pending` follows it.
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pending = PendingAttachments<String>()

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
                    pendingImages: pending.attachments,
                    onRemoveImage: removeImage,
                    onAdd: { isAddingImages = true },
                    isBusy: session.isBusy,
                    canSend: canSend,
                    onSend: send,
                    onStop: { session.stop() }
                )
            }
        }
        .sheet(isPresented: $isAddingImages) {
            AddToMessageSheet(selection: $pickerItems, maxSelectionCount: ChatSession.maxImagesPerMessage)
        }
        .onChange(of: pickerItems) { _, items in
            loadPicked(items)
        }
    }
}

private extension ChatView {
    var canSend: Bool {
        !pending.isEmpty || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() {
        let text = draft
        let images = pending.attachments
        draft = ""
        pending.clear()
        pickerItems = []
        Task { await session.send(text, images: images) }
    }

    /// Loads the newly picked photos into the composer and drops the deselected ones.
    func loadPicked(_ items: [PhotosPickerItem]) {
        // The shared photo library gives every item an identifier.
        let toLoad = pending.select(items.compactMap(\.itemIdentifier))
        for item in items {
            guard let id = item.itemIdentifier, toLoad.contains(id) else { continue }
            Task {
                let attachment = await ImageAttachmentLoader.attachment(from: item)
                pending.finishLoading(id, attachment: attachment)
            }
        }
    }

    func removeImage(at index: Int) {
        let id = pending.entries[index].id
        let remaining = Set(pending.remove(id))
        pickerItems.removeAll { $0.itemIdentifier.map { !remaining.contains($0) } ?? true }
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
