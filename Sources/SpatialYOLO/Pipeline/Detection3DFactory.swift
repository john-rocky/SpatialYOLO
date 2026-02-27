import Foundation
import CoreGraphics
import simd

/// Lifts 2D detections to 3D using depth data.
/// Implements quality gates, size estimation, and 3D→2D consistency checks.
struct Detection3DFactory {

    let config: SpatialYOLOConfig

    /// Lift an array of 2D detections to 3D using the depth provider.
    func createDetections3D(
        from detections: [Detection2D],
        depthProvider: DepthProvider
    ) -> [Detection3D] {
        var observations: [Detection3D] = []

        for detection in detections {
            guard detection.confidence >= config.minDetectionConfidence else { continue }

            // Skip boxes at screen edge
            guard !ProjectionUtils.isAtScreenEdge(detection.boundingBox, margin: config.screenEdgeMargin) else {
                continue
            }

            // Depth sampling region: center band of bbox with horizontal inset
            let bbox = detection.boundingBox
            let horizontalInset = bbox.width * config.depthHorizontalInset
            let bandTop = bbox.minY + bbox.height * config.depthSamplingBand.top
            let bandBottom = bbox.minY + bbox.height * config.depthSamplingBand.bottom

            let samplingRegion = CGRect(
                x: bbox.minX + horizontalInset,
                y: bandTop,
                width: bbox.width - horizontalInset * 2,
                height: bandBottom - bandTop
            )

            // Grid-based depth sampling
            guard let depthSample = depthProvider.sampleDepthStatsGrid(
                in: samplingRegion,
                gridRows: config.depthGridRows,
                gridCols: config.depthGridCols
            ) else { continue }

            let depthQuality = computeDepthQuality(sample: depthSample, distance: depthSample.median)

            guard depthQuality >= config.minDepthQuality,
                  depthSample.validRatio >= config.minDepthValidRatio else { continue }

            // Unproject bbox center at median depth to get world position
            let bboxCenter = CGPoint(x: bbox.midX, y: bbox.midY)
            guard let worldPos = depthProvider.worldPosition(at: bboxCenter, depth: depthSample.median) else { continue }

            // Reject NaN/Inf
            guard worldPos.x.isFinite && worldPos.y.isFinite && worldPos.z.isFinite else { continue }

            // Estimate physical size
            guard let sizeEstimate = depthProvider.estimatePhysicalSize(for: bbox, depth: depthSample.median) else { continue }

            guard sizeEstimate.height >= config.minPhysicalHeightMeters else { continue }

            // 3D→2D consistency gate
            var gateResult: GatePassResult = .skipped
            var projection2D: CGPoint?
            var projectionErrorNorm: Float?

            if let p2D = depthProvider.projectWorldToScreen(worldPos, allowOffscreen: true) {
                projection2D = p2D
                let errorX = abs(p2D.x - bboxCenter.x)
                let errorY = abs(p2D.y - bboxCenter.y)
                let toleranceX = config.gate2DToleranceX * bbox.width
                let toleranceY = config.gate2DToleranceY * bbox.height

                let errXRatio = errorX / bbox.width
                let errYRatio = errorY / bbox.height
                projectionErrorNorm = Float(max(errXRatio, errYRatio))

                if errorX <= toleranceX && errorY <= toleranceY {
                    gateResult = .passed
                } else {
                    gateResult = .failed(reason: "errX=\(String(format: "%.3f", errorX)) errY=\(String(format: "%.3f", errorY))")
                    if config.gate2DEnabled {
                        continue
                    }
                }
            }

            // Compute samplingYRatio from the 3D→2D projection
            let samplingYRatio: CGFloat
            if let p2D = projection2D {
                let rawRatio = (p2D.y - bbox.minY) / bbox.height
                samplingYRatio = max(0.1, min(0.95, rawRatio))
            } else {
                samplingYRatio = 0.5
            }

            let observation = Detection3D(
                id: detection.id,
                boundingBox: bbox,
                classLabel: detection.classLabel,
                detectionConfidence: detection.confidence,
                worldPosition: worldPos,
                depthQuality: depthQuality,
                depthStdDev: depthSample.stdDev,
                depthValidRatio: depthSample.validRatio,
                estimatedSize: sizeEstimate,
                trackID: detection.trackID,
                projection2D: projection2D,
                projectionErrorNorm: projectionErrorNorm,
                gatePassResult: gateResult,
                samplingYRatio: samplingYRatio
            )

            observations.append(observation)
        }

        return observations
    }

    // MARK: - Depth Quality

    /// Compute depth quality score (0-1) from depth statistics.
    private func computeDepthQuality(sample: DepthSample, distance: Float) -> Float {
        // Lower stdDev relative to distance = higher quality
        let relativeStdDev = sample.stdDev / max(distance, 0.1)
        // Perfect quality at stdDev=0, degrades linearly
        let stdDevScore = max(0, 1 - relativeStdDev * 10)
        // Valid ratio contributes to quality
        let validScore = sample.validRatio
        // Weighted combination
        return stdDevScore * 0.6 + validScore * 0.4
    }
}
