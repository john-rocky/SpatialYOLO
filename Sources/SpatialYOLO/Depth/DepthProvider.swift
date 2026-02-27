import ARKit
import simd

/// Protocol for providing depth-based 3D positioning from ARKit frames.
public protocol DepthProvider: AnyObject {
    /// Update with a new ARFrame.
    func updateFrame(_ frame: ARFrame)

    /// Unproject a normalized screen point (0-1, portrait/YOLO orientation) with explicit depth to world coordinates.
    func worldPosition(at normalizedPoint: CGPoint, depth: Float) -> SIMD3<Float>?

    /// Project a 3D world point to normalized screen coordinates (0-1, portrait/YOLO orientation).
    func projectWorldToScreen(_ worldPoint: SIMD3<Float>, allowOffscreen: Bool) -> CGPoint?

    /// Sample depth statistics using a sparse grid within a normalized ROI.
    func sampleDepthStatsGrid(in normalizedRect: CGRect, gridRows: Int, gridCols: Int) -> DepthSample?

    /// Estimate physical size from a normalized bounding box and depth.
    func estimatePhysicalSize(for normalizedRect: CGRect, depth: Float) -> EstimatedSize?

    /// Current camera position in world coordinates.
    var cameraPosition: SIMD3<Float> { get }

    /// Current camera intrinsics matrix.
    var intrinsics: simd_float3x3 { get }

    /// Image resolution of the current frame (landscape sensor).
    var imageResolution: CGSize { get }

    /// Camera transform (world to camera).
    var cameraTransform: simd_float4x4 { get }
}
