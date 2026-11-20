/// Where a scroll view stands relative to the end of its content.
public enum ScrollEdge {
    /// Default distance, in points, under which the reader counts as being at the bottom.
    public static let defaultTolerance = 40.0

    /// Whether the bottom of the content is in view, give or take `tolerance` points.
    ///
    /// - Parameters:
    ///   - offsetY: Vertical content offset. It starts at minus the top inset, so the bottom is reached
    ///     at `contentHeight + bottomInset - visibleHeight`.
    ///   - visibleHeight: Height of the scroll view.
    ///   - contentHeight: Height of the content, insets excluded.
    ///   - bottomInset: Bottom content inset (safe area, floating composer).
    public static func isNearBottom(
        offsetY: Double,
        visibleHeight: Double,
        contentHeight: Double,
        bottomInset: Double,
        tolerance: Double = defaultTolerance
    ) -> Bool {
        offsetY + visibleHeight >= contentHeight + bottomInset - tolerance
    }
}
