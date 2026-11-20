import SwiftUI
#if os(macOS)
    import AppKit

    /// Runs `action` on ⌘↩ before the focused text field can consume the key.
    ///
    /// A multi-line `TextField` handles Return itself, so the menu item for ⌘↩ never receives it.
    /// A local event monitor sees the key first and consumes it.
    private struct SendOnCommandReturn: ViewModifier {
        let action: () -> Void
        @State private var monitor: Any?

        func body(content: Content) -> some View {
            content
                .onAppear {
                    guard monitor == nil else { return }
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        guard event.keyCode == 36, event.modifierFlags.contains(.command) else {
                            return event
                        }
                        MainActor.assumeIsolated { action() }
                        return nil
                    }
                }
                .onDisappear {
                    if let monitor {
                        NSEvent.removeMonitor(monitor)
                    }
                    monitor = nil
                }
        }
    }
#endif

extension View {
    /// Sends on ⌘↩ from anywhere in the view, including the composer. No-op on iOS.
    @ViewBuilder
    func sendOnCommandReturn(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
            modifier(SendOnCommandReturn(action: action))
        #else
            self
        #endif
    }
}
