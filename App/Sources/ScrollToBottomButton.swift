import HermesChat
import SwiftUI

/// The round arrow that brings a conversation back to its newest message. It floats just above the
/// composer and shows only while the reader is scrolled away from the bottom.
struct ScrollToBottomButton: View {
    static let size: CGFloat = 40

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Scroll to bottom")
    }
}

/// An invisible line put after the last message. It reports whether it sits above `visibleEnd`, the
/// top of the composer, both measured on screen: the end of the conversation is then in view.
///
/// It must sit outside the lazy stack, so it is always laid out and keeps reporting while the reader
/// scrolls far from it.
struct ScrollBottomMarker: View {
    /// Top of the composer, in global coordinates.
    let visibleEnd: CGFloat
    @Binding var isAtBottom: Bool
    /// Called when the composer rises (the keyboard opens, the draft grows) while the reader was at the
    /// bottom: the screen should scroll so the last message stays just above the composer.
    var onComposerRise: () -> Void = {}

    /// Where the marker sits on screen, in global coordinates.
    @State private var contentEnd: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { newEnd in
                contentEnd = newEnd
                update()
            }
            // The composer moves too: with the keyboard, or when it grows with the draft or images.
            .onChange(of: visibleEnd) { oldEnd, newEnd in
                if isAtBottom, newEnd < oldEnd {
                    // Stay at the bottom: the scroll brings the marker back above the composer.
                    onComposerRise()
                } else {
                    update()
                }
            }
    }

    private func update() {
        let atBottom = ScrollEdge.isNearBottom(contentEnd: contentEnd, visibleEnd: visibleEnd)
        guard atBottom != isAtBottom else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isAtBottom = atBottom
        }
    }
}

extension View {
    /// Reports the top of this view (the composer inset) in global coordinates, for `ScrollBottomMarker`.
    func reportsTop(_ top: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { newTop in
            top.wrappedValue = newTop
        }
    }

    /// Floats the scroll-to-bottom button above this view (the composer inset), centered, while
    /// `isVisible` is `true`. The button sits wholly above the view's top edge, and does not change the
    /// view's height, so the messages do not jump.
    func scrollToBottomButton(isVisible: Bool, action: @escaping () -> Void) -> some View {
        overlay(alignment: .top) {
            if isVisible {
                ScrollToBottomButton(action: action)
                    .offset(y: -(ScrollToBottomButton.size + 10))
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
