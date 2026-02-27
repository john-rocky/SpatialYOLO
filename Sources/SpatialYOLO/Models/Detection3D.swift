import Foundation
import CoreGraphics
import simd

/// Result of the 3D→2D consistency gate check.
public enum GatePassResult: Sendable {
    case passed
    case failed(reason: String)
    case skipped

    public var isPass: Bool {
        if case .passed = self { return true }
        return false
    }
}

/// A 2D detection lifted to 3D using depth data.
public struct Detection3D: Identifiable, Sendable {
    public let id: UUID
    /// Original 2D bounding box (normalized 0-1, top-left origin)
    public let boundingBox: CGRect
    /// Class label
    public let classLabel: String
    /// Detection confidence
    public let detectionConfidence: Float
    /// 3D world position
    public let worldPosition: SIMD3<Float>
    /// Depth quality score (0-1)
    public let depthQuality: Float
    /// Depth standard deviation
    public let depthStdDev: Float
    /// Ratio of valid depth samples
    public let depthValidRatio: Float
    /// Estimated physical size
    public let estimatedSize: EstimatedSize
    /// 2D tracker ID
    public let trackID: Int?
    /// 2D projection of the 3D position (normalized)
    public let projection2D: CGPoint?
    /// Projection error normalized by bbox dimensions
    public let projectionErrorNorm: Float?
    /// Gate check result
    public let gatePassResult: GatePassResult
    /// Where within bbox the depth was sampled (0=top, 1=bottom)
    public let samplingYRatio: CGFloat

    public init(
        id: UUID,
        boundingBox: CGRect,
        classLabel: String,
        detectionConfidence: Float,
        worldPosition: SIMD3<Float>,
        depthQuality: Float,
        depthStdDev: Float,
        depthValidRatio: Float,
        estimatedSize: EstimatedSize,
        trackID: Int?,
        projection2D: CGPoint?,
        projectionErrorNorm: Float?,
        gatePassResult: GatePassResult,
        samplingYRatio: CGFloat
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.classLabel = classLabel
        self.detectionConfidence = detectionConfidence
        self.worldPosition = worldPosition
        self.depthQuality = depthQuality
        self.depthStdDev = depthStdDev
        self.depthValidRatio = depthValidRatio
        self.estimatedSize = estimatedSize
        self.trackID = trackID
        self.projection2D = projection2D
        self.projectionErrorNorm = projectionErrorNorm
        self.gatePassResult = gatePassResult
        self.samplingYRatio = samplingYRatio
    }
}
