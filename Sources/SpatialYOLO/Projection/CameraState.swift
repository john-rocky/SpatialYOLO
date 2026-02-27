import ARKit
import simd

/// Snapshot of ARCamera state for projection calculations.
/// Caches the view matrix for efficient batch projections within a single frame.
public struct CameraState {
    public let transform: simd_float4x4
    public let intrinsics: simd_float3x3
    public let imageResolution: CGSize

    /// Cached inverse of transform (view matrix)
    private let viewMatrix: simd_float4x4

    public init(camera: ARCamera) {
        self.transform = camera.transform
        self.intrinsics = camera.intrinsics
        self.imageResolution = camera.imageResolution
        self.viewMatrix = camera.viewMatrix(for: .landscapeRight)
    }

    /// Project a 3D bounding box (center + size) to a 2D screen rect.
    /// Handles portrait↔landscape coordinate rotation and samplingYRatio offset.
    ///
    /// - Parameters:
    ///   - center: World position of the object center
    ///   - size: Estimated physical size
    ///   - samplingYRatio: Where within bbox depth was sampled (0=top, 1=bottom)
    /// - Returns: Projected rect in normalized portrait coordinates (0-1), or nil if behind camera
    public func project3DBoxToScreen(
        center: SIMD3<Float>,
        size: EstimatedSize,
        samplingYRatio: CGFloat = 0.5
    ) -> CGRect? {
        let centerCamera4 = viewMatrix * SIMD4<Float>(center.x, center.y, center.z, 1)
        let centerCamera = SIMD3<Float>(centerCamera4.x, centerCamera4.y, centerCamera4.z)

        // Must be in front of camera
        guard centerCamera.z < 0 else { return nil }
        let depth = -centerCamera.z

        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        // In Portrait mode, the Camera Sensor is Landscape.
        // World Width (Horizontal) → Sensor Height (Camera Y) → swap
        // World Height (Vertical) → Sensor Width (Camera X) → swap
        let pixelW = (fx * size.height) / depth
        let pixelH = (fy * size.width) / depth

        let pixelX = fx * centerCamera.x / depth + cx
        let pixelY = fy * centerCamera.y / depth + cy

        let normX = CGFloat(pixelX) / imageResolution.width
        let normY = CGFloat(pixelY) / imageResolution.height
        let normW = CGFloat(pixelW) / imageResolution.width
        let normH = CGFloat(pixelH) / imageResolution.height

        // Landscape (ARKit) → Portrait (YOLO): (x,y) → (y,x), (w,h) → (h,w)
        let portraitCenterX = normY
        let portraitCenterY = normX
        let portraitW = normH
        let portraitH = normW

        // samplingYRatio: 0=top of bbox, 1=bottom
        // box top (minY) = centerY - height * samplingYRatio
        return CGRect(
            x: portraitCenterX - portraitW / 2,
            y: portraitCenterY - portraitH * samplingYRatio,
            width: portraitW,
            height: portraitH
        )
    }

    /// Project a single 3D world point to normalized portrait screen coordinates.
    public func projectWorldToScreen(_ worldPoint: SIMD3<Float>, allowOffscreen: Bool = false) -> CGPoint? {
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        let wp4 = SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let cp4 = viewMatrix * wp4
        guard cp4.z < 0 else { return nil }

        let screenX = fx * cp4.x / (-cp4.z) + cx
        let screenY = fy * cp4.y / (-cp4.z) + cy

        let normalizedX = CGFloat(screenX) / imageResolution.width
        let normalizedY = CGFloat(screenY) / imageResolution.height

        if !allowOffscreen {
            guard normalizedX >= 0, normalizedX <= 1,
                  normalizedY >= 0, normalizedY <= 1 else { return nil }
        }

        // Landscape → Portrait: (x,y) → (y,x)
        return CGPoint(x: normalizedY, y: normalizedX)
    }

    /// Distance from camera to a world point.
    public func distanceToCamera(_ worldPoint: SIMD3<Float>) -> Float {
        let camPos = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        return simd_distance(camPos, worldPoint)
    }
}
