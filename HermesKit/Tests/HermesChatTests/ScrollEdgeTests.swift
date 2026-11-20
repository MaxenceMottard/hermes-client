import Testing

@testable import HermesChat

@Suite("Scroll edge")
struct ScrollEdgeTests {
    // The composer's top edge sits at y = 600 on screen.

    @Test("content ending at the composer is at the bottom")
    func atEnd() {
        #expect(ScrollEdge.isNearBottom(contentEnd: 600, visibleEnd: 600))
    }

    @Test("content ending a few points under the composer still counts as the bottom")
    func withinTolerance() {
        #expect(ScrollEdge.isNearBottom(contentEnd: 630, visibleEnd: 600))
    }

    @Test("content going on under the composer is not at the bottom")
    func scrolledUp() {
        #expect(!ScrollEdge.isNearBottom(contentEnd: 700, visibleEnd: 600))
        #expect(!ScrollEdge.isNearBottom(contentEnd: 5_000, visibleEnd: 600))
    }

    @Test("content shorter than the screen, ending above the composer, is at the bottom")
    func shortContent() {
        #expect(ScrollEdge.isNearBottom(contentEnd: 200, visibleEnd: 600))
    }
}
