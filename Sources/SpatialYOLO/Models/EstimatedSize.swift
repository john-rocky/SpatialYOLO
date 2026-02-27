import Foundation

/// Estimated physical dimensions of a detected object in meters.
public struct EstimatedSize: Sendable {
    /// Physical width in meters
    public var width: Float
    /// Physical height in meters
    public var height: Float

    /// Area in square meters
    public var area: Float { width * height }

    public init(width: Float, height: Float) {
        self.width = width
        self.height = height
    }

    /// EMA update
    func blended(with other: EstimatedSize, alpha: Float) -> EstimatedSize {
        EstimatedSize(
            width: width * (1 - alpha) + other.width * alpha,
            height: height * (1 - alpha) + other.height * alpha
        )
    }
}
