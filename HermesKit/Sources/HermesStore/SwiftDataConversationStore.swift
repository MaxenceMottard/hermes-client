#if canImport(SwiftData)
    import Foundation
    import SwiftData

    /// SwiftData model: one conversation, with its messages ordered by `index`.
    @Model
    final class ConversationRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        /// Optional so that stores created before this field existed migrate without a custom plan.
        var model: String?
        /// Optional for the same reason as `model`.
        var provider: String?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
        var messages: [MessageRecord]

        init(id: UUID, title: String, model: String?, provider: String?, createdAt: Date, updatedAt: Date) {
            self.id = id
            self.title = title
            self.model = model
            self.provider = provider
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            messages = []
        }
    }

    /// SwiftData model: one message. `index` is its position in the conversation.
    @Model
    final class MessageRecord {
        var index: Int
        var role: String
        var content: String
        var conversation: ConversationRecord?

        init(index: Int, role: String, content: String) {
            self.index = index
            self.role = role
            self.content = content
        }
    }

    /// `ConversationStore` backed by SwiftData. Use `makeContainer` to create the container.
    @MainActor
    public final class SwiftDataConversationStore: ConversationStore {
        /// Kept alive on purpose: a `ModelContext` does not retain its container, and saving after the
        /// container is released traps inside SwiftData.
        private let container: ModelContainer
        private let context: ModelContext

        public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
            let schema = Schema([ConversationRecord.self, MessageRecord.self])
            let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        public init(container: ModelContainer) {
            self.container = container
            context = container.mainContext
        }

        public func summaries() throws -> [ConversationSummary] {
            var descriptor = FetchDescriptor<ConversationRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            descriptor.propertiesToFetch = [\.id, \.title, \.model, \.provider, \.updatedAt]
            return try context.fetch(descriptor).map {
                ConversationSummary(
                    id: $0.id, title: $0.title, model: $0.model, provider: $0.provider, updatedAt: $0.updatedAt)
            }
        }

        public func conversation(id: UUID) throws -> StoredConversation? {
            guard let record = try record(id: id) else { return nil }
            return StoredConversation(
                id: record.id,
                title: record.title,
                model: record.model,
                provider: record.provider,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                messages: record.messages
                    .sorted { $0.index < $1.index }
                    .map { StoredMessage(role: $0.role, content: $0.content) }
            )
        }

        @discardableResult
        public func createConversation(title: String, model: String?, provider: String?) throws -> StoredConversation {
            let date = Date()
            let record = ConversationRecord(
                id: UUID(), title: title, model: model, provider: provider, createdAt: date, updatedAt: date
            )
            context.insert(record)
            try context.save()
            return StoredConversation(
                id: record.id, title: title, model: model, provider: provider,
                createdAt: date, updatedAt: date, messages: []
            )
        }

        public func replaceMessages(_ messages: [StoredMessage], inConversation id: UUID) throws {
            guard let record = try record(id: id) else {
                throw ConversationStoreError.notFound(id)
            }
            for old in record.messages {
                context.delete(old)
            }
            record.messages = messages.enumerated().map { offset, message in
                MessageRecord(index: offset, role: message.role, content: message.content)
            }
            record.updatedAt = Date()
            try context.save()
        }

        public func rename(conversation id: UUID, to title: String) throws {
            guard let record = try record(id: id) else {
                throw ConversationStoreError.notFound(id)
            }
            record.title = title
            try context.save()
        }

        public func deleteConversation(id: UUID) throws {
            guard let record = try record(id: id) else {
                throw ConversationStoreError.notFound(id)
            }
            context.delete(record)
            try context.save()
        }

        private func record(id: UUID) throws -> ConversationRecord? {
            var descriptor = FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }
    }
#endif
