/// Where a scroll view stands relative to the end of its content.
public enum ScrollEdge {
    /// Default distance, in points, under which the reader counts as being at the bottom.
    public static let defaultTolerance = 40.0

    /// Whether the end of the content is in view, give or take `tolerance` points.
    ///
    /// Both positions are vertical coordinates in the same space, growing downwards:
    /// - Parameters:
    ///   - contentEnd: Where the content ends (the bottom of the last message).
    ///   - visibleEnd: Where the visible part ends: the top of whatever covers the bottom of the
    ///     scroll view, such as the floating composer.
    public static func isNearBottom(
        contentEnd: Double,
        visibleEnd: Double,
        tolerance: Double = defaultTolerance
    ) -> Bool {
        contentEnd <= visibleEnd + tolerance
    }
}
