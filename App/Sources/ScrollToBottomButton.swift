import HermesChat
import SwiftUI

/// The round arrow that brings a conversation back to its newest message. It floats just above the
/// composer and shows only while the reader is scrolled away from the bottom.
struct ScrollToBottomButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Scroll to bottom")
    }
}

extension View {
    /// Keeps `isAtBottom` in step with the scroll position: `true` while the end of the content is in
    /// view, composer inset included. See `ScrollEdge.isNearBottom`.
    func tracksScrollBottom(_ isAtBottom: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            ScrollEdge.isNearBottom(
                offsetY: geometry.contentOffset.y,
                visibleHeight: geometry.containerSize.height,
                contentHeight: geometry.contentSize.height,
                bottomInset: geometry.contentInsets.bottom
            )
        } action: { _, atBottom in
            withAnimation(.easeInOut(duration: 0.2)) {
                isAtBottom.wrappedValue = atBottom
            }
        }
    }

    /// Floats the scroll-to-bottom button above this view (the composer inset), centered, while
    /// `isVisible` is `true`. It does not change the inset's height, so the messages do not jump.
    func scrollToBottomButton(isVisible: Bool, action: @escaping () -> Void) -> some View {
        overlay(alignment: .top) {
            if isVisible {
                ScrollToBottomButton(action: action)
                    .alignmentGuide(.top) { $0[.bottom] + 10 }
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
