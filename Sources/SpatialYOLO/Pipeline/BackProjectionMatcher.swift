import Foundation
import CoreGraphics
import simd

/// Result of back-projection matching.
struct MatchResult {
    /// Matched pairs: (tracked object ID, detection 3D)
    var matched: [(objectID: UUID, detection: Detection3D)] = []
    /// Unmatched new detections (not assigned to any existing object)
    var unmatchedDetections: [Detection3D] = []
    /// IDs of existing objects that were not observed this frame
    var missedObjectIDs: [UUID] = []
}

/// Projects existing tracked objects to 2D, then matches with new 3D detections using two-stage IoU.
struct BackProjectionMatcher {

    let config: SpatialYOLOConfig

    /// Match incoming 3D detections against projected existing tracked objects.
    func match(
        objects: [TrackedObject],
        detections: [Detection3D],
        camera: CameraState
    ) -> MatchResult {
        var result = MatchResult()

        // Match against all non-lost objects (including candidates for promotion)
        let activeObjects = objects.filter { $0.state != .lost }

        guard !activeObjects.isEmpty && !detections.isEmpty else {
            result.unmatchedDetections = detections
            result.missedObjectIDs = activeObjects.map { $0.id }
            return result
        }

        // Project all active objects to 2D screen rects
        struct Projection {
            let objectID: UUID
            let rect: CGRect
            let object: TrackedObject
        }

        var projections: [Projection] = []
        for object in activeObjects {
            let extendedBounds = object.state == .confirmed ? 0.1 : config.extendedScreenBounds
            guard let rect = camera.project3DBoxToScreen(
                center: object.worldPosition,
                size: object.estimatedSize,
                samplingYRatio: object.samplingYRatio
            ) else { continue }

            // Check within extended screen bounds
            guard rect.minX >= -extendedBounds, rect.maxX <= 1.0 + extendedBounds,
                  rect.minY >= -extendedBounds, rect.maxY <= 1.0 + extendedBounds else { continue }

            projections.append(Projection(objectID: object.id, rect: rect, object: object))
        }

        guard !projections.isEmpty else {
            result.unmatchedDetections = detections
            result.missedObjectIDs = activeObjects.map { $0.id }
            return result
        }

        var usedProjectionIndices = Set<Int>()
        var usedDetectionIndices = Set<Int>()

        // Stage 1: High IoU matches with early termination
        for (dIdx, detection) in detections.enumerated() {
            for (pIdx, projection) in projections.enumerated() {
                guard !usedProjectionIndices.contains(pIdx) else { continue }

                let iou = ProjectionUtils.calculateIoU(projection.rect, detection.boundingBox)
                if iou >= config.highIoUThreshold {
                    result.matched.append((objectID: projection.objectID, detection: detection))
                    usedProjectionIndices.insert(pIdx)
                    usedDetectionIndices.insert(dIdx)
                    break
                }
            }
        }

        // Stage 2: Remaining pairs sorted by composite score, greedy match
        struct Candidate {
            let pIdx: Int
            let dIdx: Int
            let iou: Float
            let compositeScore: Float
        }

        var candidates: [Candidate] = []

        for (dIdx, detection) in detections.enumerated() {
            guard !usedDetectionIndices.contains(dIdx) else { continue }

            for (pIdx, projection) in projections.enumerated() {
                guard !usedProjectionIndices.contains(pIdx) else { continue }

                let iou = ProjectionUtils.calculateIoU(projection.rect, detection.boundingBox)
                guard iou >= config.minIoUForMatch else { continue }

                let centerDist = ProjectionUtils.centerDistance(projection.rect, detection.boundingBox)
                let maxDist = config.maxCenterDistance
                let centerScore = Float(max(0, 1.0 - centerDist / maxDist))
                let compositeScore = centerScore * 0.8 + iou * 0.2

                candidates.append(Candidate(pIdx: pIdx, dIdx: dIdx, iou: iou, compositeScore: compositeScore))
            }
        }

        // Sort by composite score descending
        candidates.sort { $0.compositeScore > $1.compositeScore }

        for candidate in candidates {
            guard !usedProjectionIndices.contains(candidate.pIdx),
                  !usedDetectionIndices.contains(candidate.dIdx) else { continue }

            let projection = projections[candidate.pIdx]
            let detection = detections[candidate.dIdx]

            result.matched.append((objectID: projection.objectID, detection: detection))
            usedProjectionIndices.insert(candidate.pIdx)
            usedDetectionIndices.insert(candidate.dIdx)
        }

        // Collect unmatched detections
        result.unmatchedDetections = detections.enumerated()
            .filter { !usedDetectionIndices.contains($0.offset) }
            .map { $0.element }

        // Collect missed object IDs
        let matchedObjectIDs = Set(result.matched.map { $0.objectID })
        result.missedObjectIDs = activeObjects
            .filter { !matchedObjectIDs.contains($0.id) }
            .map { $0.id }

        return result
    }
}
