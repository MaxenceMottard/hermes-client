import HermesChat
import SwiftUI

/// What the menu bar can do in the focused window: the enabled state of each command, and the way to run it.
/// Published by `ConversationsView` with `focusedSceneValue`, so the menu items follow the open conversation.
struct ChatMenuActions {
    let enabled: Set<ChatCommand>
    let perform: @MainActor (ChatCommand) -> Void
}

private struct ChatMenuActionsKey: FocusedValueKey {
    typealias Value = ChatMenuActions
}

extension FocusedValues {
    var chatMenuActions: ChatMenuActions? {
        get { self[ChatMenuActionsKey.self] }
        set { self[ChatMenuActionsKey.self] = newValue }
    }
}

/// Menu bar entries and their shortcuts: ⌘N new conversation (File menu), ⌘↩ send and ⌘. stop (Chat menu).
struct ChatMenuCommands: Commands {
    @FocusedValue(\.chatMenuActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Conversation") {
                actions?.perform(.newConversation)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!isEnabled(.newConversation))
        }

        CommandMenu("Chat") {
            Button("Send Message") {
                actions?.perform(.send)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isEnabled(.send))

            Button("Stop Reply") {
                actions?.perform(.stop)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!isEnabled(.stop))
        }
    }

    private func isEnabled(_ command: ChatCommand) -> Bool {
        actions?.enabled.contains(command) ?? false
    }
}
