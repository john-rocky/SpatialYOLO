import Foundation

/// Depth sampling statistics from a grid of points within an ROI.
public struct DepthSample: Sendable {
    /// p25 depth (nearest quartile)
    public let nearDepth: Float
    /// p50 depth (median)
    public let median: Float
    /// p75 depth (far quartile)
    public let farDepth: Float
    /// Standard deviation of valid depth samples
    public let stdDev: Float
    /// Ratio of valid samples to total grid points
    public let validRatio: Float
    /// Number of valid depth samples
    public let validCount: Int
    /// Total number of grid points sampled
    public let totalCount: Int
}
