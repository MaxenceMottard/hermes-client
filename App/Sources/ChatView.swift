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
    /// Ids of the photos taken with the camera, in the order taken. They are not part of the picker selection.
    @State private var cameraIDs: [String] = []
    @State private var pending = PendingAttachments<String>()
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                    MessageRow(message: message)
                }
            }
            .padding()
        }
        // Before the inset, so a tap on the composer does not hide the keyboard.
        .dismissesKeyboard($isComposerFocused)
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
                    isFocused: $isComposerFocused,
                    pendingImages: pending.attachments,
                    onRemoveImage: removeImage,
                    onAdd: { isAddingImages = true },
                    model: session.modelChoice,
                    isBusy: session.isBusy,
                    canSend: canSend,
                    onSend: send,
                    onStop: { session.stop() }
                )
            }
        }
        .sheet(isPresented: $isAddingImages) {
            AddToMessageSheet(
                selection: $pickerItems,
                maxSelectionCount: max(1, ChatSession.maxImagesPerMessage - cameraIDs.count),
                canAddPhoto: pending.entries.count < ChatSession.maxImagesPerMessage,
                onPhotoTaken: addCameraPhoto
            )
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
        cameraIDs = []
        Task { await session.send(text, images: images) }
    }

    /// Everything the composer should hold: the picked photos, then the camera photos.
    func selectedIDs(_ items: [PhotosPickerItem]) -> [String] {
        // The shared photo library gives every item an identifier.
        items.compactMap(\.itemIdentifier) + cameraIDs
    }

    /// Loads the newly picked photos into the composer and drops the deselected ones.
    func loadPicked(_ items: [PhotosPickerItem]) {
        // Camera photos count against the limit too: trim the picks that do not fit.
        let room = ChatSession.maxImagesPerMessage - cameraIDs.count
        if items.count > room {
            pickerItems = Array(items.prefix(max(0, room)))
            return
        }
        let toLoad = pending.select(selectedIDs(items))
        for item in items {
            guard let id = item.itemIdentifier, toLoad.contains(id) else { continue }
            Task {
                let attachment = await ImageAttachmentLoader.attachment(from: item)
                pending.finishLoading(id, attachment: attachment)
            }
        }
    }

    /// Adds a photo taken with the camera, downscaled like a picked one.
    func addCameraPhoto(_ data: Data) {
        guard pending.entries.count < ChatSession.maxImagesPerMessage,
              let attachment = ImageAttachmentLoader.jpegAttachment(from: data)
        else { return }
        let id = "camera-\(UUID().uuidString)"
        cameraIDs.append(id)
        _ = pending.select(selectedIDs(pickerItems))
        pending.finishLoading(id, attachment: attachment)
    }

    func removeImage(at index: Int) {
        let id = pending.entries[index].id
        cameraIDs.removeAll { $0 == id }
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
