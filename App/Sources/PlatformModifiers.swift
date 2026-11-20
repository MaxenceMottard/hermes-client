import SwiftUI

extension View {
    /// Inline navigation title. `navigationBarTitleDisplayMode` exists only on iOS, so this is a no-op on macOS.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    /// Hides the tab bar while this view is shown on a compact width, where it fills the screen (a pushed
    /// conversation on iPhone). On regular widths the view shares the screen with others that need the tab
    /// bar, so it stays. macOS shows tabs in the window toolbar: no-op there.
    func hidesTabBarWhenCompact() -> some View {
        modifier(CompactTabBarHider())
    }

    /// Hides the keyboard of a conversation screen two ways: a tap anywhere in the messages, and the
    /// native interactive dismiss, where the keyboard follows a finger dragging down past its top edge.
    /// iOS only: macOS has no software keyboard.
    @ViewBuilder
    func dismissesKeyboard(_ focus: FocusState<Bool>.Binding) -> some View {
        #if os(iOS)
            scrollDismissesKeyboard(.interactively)
                // Simultaneous, so links and buttons in the messages still get their taps.
                .simultaneousGesture(
                    TapGesture().onEnded {
                        focus.wrappedValue = false
                    }
                )
        #else
            self
        #endif
    }
}

private struct CompactTabBarHider: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
            content.toolbar(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        #else
            content
        #endif
    }
}
