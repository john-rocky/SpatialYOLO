import Foundation
import simd

/// Manages the lifecycle of tracked objects (slots).
/// Handles creation, EMA updates, proximity recapture, and state transitions.
final class SlotManager {

    let config: SpatialYOLOConfig

    /// All tracked objects (never deleted, transition through lifecycle states)
    private(set) var objects: [TrackedObject] = []

    init(config: SpatialYOLOConfig) {
        self.config = config
    }

    /// Get a tracked object by ID.
    func object(byID id: UUID) -> TrackedObject? {
        objects.first { $0.id == id }
    }

    /// Update a matched object with a new observation (EMA smoothing).
    func updateObject(id: UUID, with detection: Detection3D) {
        guard let object = object(byID: id) else { return }
        object.updateWith(
            observation: detection,
            positionAlpha: config.positionAlpha,
            sizeAlpha: config.sizeAlpha,
            confidenceAlpha: config.confidenceAlpha
        )
    }

    /// Attempt to recapture stale/lost objects using 3D proximity.
    /// Returns the IDs of recaptured objects and removes matched detections from the unmatched list.
    func attemptRecapture(unmatchedDetections: inout [Detection3D]) -> [UUID] {
        let recapturable = objects.filter { $0.state == .stale || $0.state == .lost }
        guard !recapturable.isEmpty else { return [] }

        var recapturedIDs: [UUID] = []
        var usedDetectionIndices = Set<Int>()

        for object in recapturable {
            var bestIdx: Int?
            var bestDist: Float = config.recaptureDistance

            for (idx, detection) in unmatchedDetections.enumerated() {
                guard !usedDetectionIndices.contains(idx) else { continue }

                let dist = object.distance(to: detection.worldPosition)
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = idx
                }
            }

            if let idx = bestIdx {
                let detection = unmatchedDetections[idx]
                object.updateWith(
                    observation: detection,
                    positionAlpha: config.positionAlpha,
                    sizeAlpha: config.sizeAlpha,
                    confidenceAlpha: config.confidenceAlpha
                )
                usedDetectionIndices.insert(idx)
                recapturedIDs.append(object.id)
            }
        }

        // Remove used detections (iterate in reverse to maintain indices)
        for idx in usedDetectionIndices.sorted().reversed() {
            unmatchedDetections.remove(at: idx)
        }

        return recapturedIDs
    }

    /// Create new candidate objects for unmatched detections.
    /// Performs proximity deduplication to avoid creating near-duplicates.
    func createCandidates(from detections: [Detection3D]) {
        for detection in detections {
            // Check minimum distance to all existing objects
            let tooClose = objects.contains { obj in
                obj.state != .lost && obj.distance(to: detection.worldPosition) < config.minNewCandidateDistance
            }
            guard !tooClose else { continue }

            let newObject = TrackedObject(
                classLabel: detection.classLabel,
                worldPosition: detection.worldPosition,
                estimatedSize: detection.estimatedSize,
                confidence: detection.detectionConfidence,
                samplingYRatio: detection.samplingYRatio
            )
            newObject.confirmationThreshold = config.confirmationFrames
            newObject.staleThreshold = config.staleFrames
            newObject.lostThreshold = config.lostFrames
            objects.append(newObject)
        }
    }

    /// Advance lifecycle for objects that were missed this frame.
    func advanceLifecycle(missedIDs: [UUID]) {
        for id in missedIDs {
            guard let object = object(byID: id) else { continue }
            object.markMissed()
        }
    }

    /// Get all visible objects (not lost).
    var visibleObjects: [TrackedObject] {
        objects.filter { $0.state != .lost }
    }

    /// Get confirmed objects only.
    var confirmedObjects: [TrackedObject] {
        objects.filter { $0.state == .confirmed }
    }

    /// Remove lost objects to prevent unbounded array growth.
    func purgeLostObjects() {
        objects.removeAll { $0.state == .lost }
    }
}
