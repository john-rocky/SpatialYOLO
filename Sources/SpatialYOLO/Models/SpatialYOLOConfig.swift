import Foundation
import CoreGraphics

/// All tunable parameters for the SpatialYOLO pipeline.
public struct SpatialYOLOConfig: Sendable {

    // MARK: - Detection Filtering
    /// Minimum detection confidence to process
    public var minDetectionConfidence: Float = 0.35
    /// Minimum physical height in meters to accept
    public var minPhysicalHeightMeters: Float = 0.02

    // MARK: - Depth Sampling
    /// Grid rows for depth sampling
    public var depthGridRows: Int = 3
    /// Grid columns for depth sampling
    public var depthGridCols: Int = 6
    /// Minimum depth quality score (0-1)
    public var minDepthQuality: Float = 0.4
    /// Minimum valid depth sample ratio
    public var minDepthValidRatio: Float = 0.3
    /// Horizontal inset ratio for sampling region (0.2 = 20% from each side)
    public var depthHorizontalInset: CGFloat = 0.2
    /// Sampling band within bbox (top, bottom) as ratios
    public var depthSamplingBand: (top: CGFloat, bottom: CGFloat) = (0.30, 0.70)

    // MARK: - 3D→2D Gate
    /// Enable the 3D→2D consistency gate
    public var gate2DEnabled: Bool = true
    /// X tolerance as multiple of bbox width
    public var gate2DToleranceX: CGFloat = 0.5
    /// Y tolerance as multiple of bbox height
    public var gate2DToleranceY: CGFloat = 0.5

    // MARK: - Screen Edge Filtering
    /// Reject detections within this margin of screen edge (normalized)
    public var screenEdgeMargin: CGFloat = 0.01

    // MARK: - Back-Projection Matching
    /// High IoU threshold for immediate match (stage 1)
    public var highIoUThreshold: Float = 0.75
    /// Minimum IoU for fallback match (stage 2)
    public var minIoUForMatch: Float = 0.1
    /// Maximum center distance for match consideration
    public var maxCenterDistance: CGFloat = 0.4

    // MARK: - Slot Lifecycle
    /// EMA alpha for position smoothing
    public var positionAlpha: Float = 0.15
    /// EMA alpha for size smoothing
    public var sizeAlpha: Float = 0.15
    /// EMA alpha for confidence smoothing
    public var confidenceAlpha: Float = 0.15
    /// Consecutive frames to confirm a candidate
    public var confirmationFrames: Int = 3
    /// Missed frames before confirmed→stale
    public var staleFrames: Int = 15
    /// Missed frames before stale→lost
    public var lostFrames: Int = 90

    // MARK: - 3D Proximity Recapture
    /// 3D distance threshold for recapture (meters)
    public var recaptureDistance: Float = 0.08
    /// Minimum 3D distance to create new candidate (avoid duplication)
    public var minNewCandidateDistance: Float = 0.05

    // MARK: - Billboard Display
    /// Extended screen bounds for projecting stale/lost objects
    public var extendedScreenBounds: CGFloat = 0.3

    // MARK: - Distance Visual Feedback
    /// Distance threshold for near range (red-orange), in meters
    public var distanceNear: Float = 0.5
    /// Distance threshold for mid range (green), in meters
    public var distanceMid: Float = 2.0
    /// Distance threshold for far range (cyan), in meters
    public var distanceFar: Float = 5.0
    /// Maximum distance for proximity bar fill (bar empty at this distance)
    public var proximityBarMaxDistance: Float = 5.0

    public static let `default` = SpatialYOLOConfig()

    public init() {}
}
