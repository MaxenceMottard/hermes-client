import Testing

@testable import HermesChat

@Suite("Scroll edge")
struct ScrollEdgeTests {
    // A 1 000 pt conversation in a 600 pt scroll view with a 150 pt composer inset: the bottom is
    // reached at offset 1 000 + 150 - 600 = 550.

    @Test("scrolled to the end is at the bottom")
    func atEnd() {
        #expect(ScrollEdge.isNearBottom(offsetY: 550, visibleHeight: 600, contentHeight: 1_000, bottomInset: 150))
    }

    @Test("a few points short of the end still counts as the bottom")
    func withinTolerance() {
        #expect(ScrollEdge.isNearBottom(offsetY: 520, visibleHeight: 600, contentHeight: 1_000, bottomInset: 150))
    }

    @Test("scrolled up past the tolerance is not at the bottom")
    func scrolledUp() {
        #expect(!ScrollEdge.isNearBottom(offsetY: 500, visibleHeight: 600, contentHeight: 1_000, bottomInset: 150))
        #expect(!ScrollEdge.isNearBottom(offsetY: 0, visibleHeight: 600, contentHeight: 1_000, bottomInset: 150))
    }

    @Test("the bottom inset counts: the end hidden under the composer is not the bottom")
    func insetCounts() {
        // Without the inset this offset would be the end; with it, 150 pt are still hidden.
        #expect(!ScrollEdge.isNearBottom(offsetY: 400, visibleHeight: 600, contentHeight: 1_000, bottomInset: 150))
    }

    @Test("content shorter than the view is always at the bottom")
    func shortContent() {
        #expect(ScrollEdge.isNearBottom(offsetY: -100, visibleHeight: 600, contentHeight: 200, bottomInset: 150))
    }

    @Test("an over-scroll past the end is at the bottom")
    func bounce() {
        #expect(ScrollEdge.isNearBottom(offsetY: 600, visibleHeight: 600, contentHeight: 1_000, bottomInset: 150))
    }
}
