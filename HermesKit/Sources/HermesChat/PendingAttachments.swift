import HermesAPI

/// The images waiting in the composer, kept in step with a picker selection.
///
/// The picker hands out item identifiers; loading an item into an `ImageAttachment` is async. This
/// tracks which selected items still need loading, drops the ones the user deselected (even while
/// they load), and keeps the images in selection order.
public struct PendingAttachments<ID: Hashable & Sendable>: Sendable {
    public struct Entry: Sendable {
        public let id: ID
        public let attachment: ImageAttachment
    }

    /// Loaded images, in selection order.
    public private(set) var entries: [Entry] = []
    private var selection: [ID] = []
    private var loading: Set<ID> = []

    public init() {}

    public var attachments: [ImageAttachment] { entries.map(\.attachment) }
    public var isEmpty: Bool { entries.isEmpty }

    /// Applies a new picker selection. Returns the identifiers to load now: selected, not loaded yet,
    /// and not already loading.
    public mutating func select(_ ids: [ID]) -> [ID] {
        selection = ids
        let selected = Set(ids)
        entries.removeAll { !selected.contains($0.id) }
        let loaded = Set(entries.map(\.id))
        let toLoad = ids.filter { !loaded.contains($0) && !loading.contains($0) }
        loading.formUnion(toLoad)
        return toLoad
    }

    /// Records the result of a load. A `nil` attachment (unreadable image) is dropped. An item
    /// deselected while it loaded is dropped too.
    public mutating func finishLoading(_ id: ID, attachment: ImageAttachment?) {
        loading.remove(id)
        guard let attachment, let rank = selection.firstIndex(of: id),
              !entries.contains(where: { $0.id == id })
        else { return }
        let insertAt = entries.firstIndex { (selection.firstIndex(of: $0.id) ?? .max) > rank } ?? entries.endIndex
        entries.insert(Entry(id: id, attachment: attachment), at: insertAt)
    }

    /// Removes one image. Returns the remaining selection, to hand back to the picker.
    public mutating func remove(_ id: ID) -> [ID] {
        entries.removeAll { $0.id == id }
        selection.removeAll { $0 == id }
        return selection
    }

    /// Empties everything, after a send. Loads still in flight are ignored when they finish.
    public mutating func clear() {
        entries = []
        selection = []
    }
}
