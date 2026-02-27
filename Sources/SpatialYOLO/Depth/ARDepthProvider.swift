import ARKit
import simd

/// ARKit LiDAR-based depth provider.
/// Handles portrait↔landscape coordinate rotation and grid-based depth sampling.
public final class ARDepthProvider: DepthProvider {

    // MARK: - Properties

    private var currentFrame: ARFrame?
    private var cachedViewMatrix: simd_float4x4?
    private var cachedFrameTimestamp: TimeInterval = 0

    public var cameraPosition: SIMD3<Float> {
        guard let frame = currentFrame else { return .zero }
        let t = frame.camera.transform
        return SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    public var intrinsics: simd_float3x3 {
        currentFrame?.camera.intrinsics ?? matrix_identity_float3x3
    }

    public var imageResolution: CGSize {
        currentFrame?.camera.imageResolution ?? CGSize(width: 1920, height: 1440)
    }

    public var cameraTransform: simd_float4x4 {
        currentFrame?.camera.transform ?? matrix_identity_float4x4
    }

    public init() {}

    // MARK: - Frame Update

    public func updateFrame(_ frame: ARFrame) {
        self.currentFrame = frame
        if frame.timestamp != cachedFrameTimestamp {
            cachedFrameTimestamp = frame.timestamp
            cachedViewMatrix = nil
        }
    }

    private func getViewMatrix(camera: ARCamera) -> simd_float4x4 {
        if let cached = cachedViewMatrix { return cached }
        let matrix = camera.viewMatrix(for: .landscapeRight)
        cachedViewMatrix = matrix
        return matrix
    }

    private func getCurrentDepthMap() -> CVPixelBuffer? {
        guard let frame = currentFrame else { return nil }
        return frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
    }

    // MARK: - World Position

    public func worldPosition(at normalizedPoint: CGPoint, depth: Float) -> SIMD3<Float>? {
        guard normalizedPoint.x.isFinite, normalizedPoint.y.isFinite else { return nil }
        guard let frame = currentFrame else { return nil }
        guard depth > 0 && depth < 10 else { return nil }
        return unprojectPoint(normalizedPoint: normalizedPoint, depth: depth, frame: frame)
    }

    private func unprojectPoint(normalizedPoint: CGPoint, depth: Float, frame: ARFrame) -> SIMD3<Float>? {
        let camera = frame.camera
        let viewportSize = camera.imageResolution

        // Portrait (YOLO) → Landscape (ARKit): (x,y) → (y,x)
        let arKitNormalized = CGPoint(x: normalizedPoint.y, y: normalizedPoint.x)

        let viewportPoint = CGPoint(
            x: arKitNormalized.x * viewportSize.width,
            y: arKitNormalized.y * viewportSize.height
        )

        let intrinsics = camera.intrinsics
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        let x = Float(viewportPoint.x)
        let y = Float(viewportPoint.y)

        let cameraX = (x - cx) * depth / fx
        let cameraY = (y - cy) * depth / fy
        let cameraZ = -depth

        let cameraPoint = SIMD4<Float>(cameraX, cameraY, cameraZ, 1)
        let worldPoint = camera.transform * cameraPoint

        let result = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
        guard result.x.isFinite && result.y.isFinite && result.z.isFinite else { return nil }
        return result
    }

    // MARK: - Projection

    public func projectWorldToScreen(_ worldPoint: SIMD3<Float>, allowOffscreen: Bool = false) -> CGPoint? {
        guard let frame = currentFrame else { return nil }
        let camera = frame.camera
        let viewMatrix = getViewMatrix(camera: camera)
        let imageSize = camera.imageResolution

        let intrinsics = camera.intrinsics
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        let worldPoint4 = SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let cameraPoint4 = viewMatrix * worldPoint4
        let cameraPoint = SIMD3<Float>(cameraPoint4.x, cameraPoint4.y, cameraPoint4.z)

        guard cameraPoint.z < 0 else { return nil }

        let screenX = fx * cameraPoint.x / (-cameraPoint.z) + cx
        let screenY = fy * cameraPoint.y / (-cameraPoint.z) + cy

        let normalizedX = CGFloat(screenX) / imageSize.width
        let normalizedY = CGFloat(screenY) / imageSize.height

        if !allowOffscreen {
            guard normalizedX >= 0, normalizedX <= 1, normalizedY >= 0, normalizedY <= 1 else { return nil }
        }

        // Landscape (ARKit) → Portrait (YOLO): (x,y) → (y,x)
        return CGPoint(x: normalizedY, y: normalizedX)
    }

    // MARK: - Grid Depth Sampling

    public func sampleDepthStatsGrid(in normalizedRect: CGRect, gridRows: Int = 3, gridCols: Int = 6) -> DepthSample? {
        guard normalizedRect.width > 0.001, normalizedRect.height > 0.001 else { return nil }
        guard let depthMap = getCurrentDepthMap() else { return nil }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let depthPointer = baseAddress.assumingMemoryBound(to: Float32.self)

        // Portrait (YOLO) → Landscape (ARKit depth): (x,y,w,h) → (y,x,h,w)
        let arKitRect = CGRect(
            x: normalizedRect.minY,
            y: normalizedRect.minX,
            width: normalizedRect.height,
            height: normalizedRect.width
        )

        var depths: [Float] = []
        depths.reserveCapacity(gridRows * gridCols)

        let stepX = arKitRect.width / CGFloat(gridCols + 1)
        let stepY = arKitRect.height / CGFloat(gridRows + 1)

        for row in 1...gridRows {
            for col in 1...gridCols {
                let normalizedX = arKitRect.minX + stepX * CGFloat(col)
                let normalizedY = arKitRect.minY + stepY * CGFloat(row)

                let pixelX = Int(normalizedX * CGFloat(width))
                let pixelY = Int(normalizedY * CGFloat(height))

                guard pixelX >= 0, pixelX < width, pixelY >= 0, pixelY < height else { continue }

                let offset = pixelY * (bytesPerRow / 4) + pixelX
                guard offset >= 0 && offset < (width * height) else { continue }
                let depth = depthPointer[offset]

                if depth > 0.1 && depth < 5.0 && depth.isFinite {
                    depths.append(depth)
                }
            }
        }

        let totalCount = gridRows * gridCols
        guard depths.count >= 3 else { return nil }

        depths.sort()
        let nearDepth = depths[depths.count / 4]
        let median = depths[depths.count / 2]
        let farDepth = depths[depths.count * 3 / 4]

        let mean = depths.reduce(0, +) / Float(depths.count)
        let variance = depths.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(depths.count)
        let stdDev = sqrt(variance)
        let validRatio = Float(depths.count) / Float(totalCount)

        return DepthSample(
            nearDepth: nearDepth,
            median: median,
            farDepth: farDepth,
            stdDev: stdDev,
            validRatio: validRatio,
            validCount: depths.count,
            totalCount: totalCount
        )
    }

    // MARK: - Physical Size Estimation

    public func estimatePhysicalSize(for normalizedRect: CGRect, depth: Float) -> EstimatedSize? {
        guard let frame = currentFrame else { return nil }
        let imageRes = frame.camera.imageResolution

        // YOLO portrait → rotated dimensions
        let rotatedWidth = Float(imageRes.height)
        let rotatedHeight = Float(imageRes.width)

        let pixelWidth = Float(normalizedRect.width) * rotatedWidth
        let pixelHeight = Float(normalizedRect.height) * rotatedHeight

        let intrinsics = frame.camera.intrinsics
        // After portrait rotation: fx(portrait) = fy(landscape), fy(portrait) = fx(landscape)
        let fxPortrait = intrinsics[1, 1]
        let fyPortrait = intrinsics[0, 0]

        guard fxPortrait > 0.001, fyPortrait > 0.001 else { return nil }

        let width = depth * (pixelWidth / fxPortrait)
        let height = depth * (pixelHeight / fyPortrait)

        return EstimatedSize(width: width, height: height)
    }
}
