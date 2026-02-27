import Foundation
import simd
import CoreGraphics

/// Lifecycle state of a tracked object.
public enum SlotState: String, Sendable {
    case candidate
    case confirmed
    case stale
    case lost
}

/// A persistent tracked object with EMA-smoothed position/size and lifecycle state.
public final class TrackedObject: Identifiable, ObservableObject {
    public let id: UUID
    /// Class label
    public let classLabel: String
    /// Current lifecycle state
    public private(set) var state: SlotState
    /// EMA-smoothed world position
    public private(set) var worldPosition: SIMD3<Float>
    /// EMA-smoothed estimated physical size
    public private(set) var estimatedSize: EstimatedSize
    /// EMA-smoothed detection confidence
    public private(set) var confidenceMean: Float
    /// Where within bbox depth was sampled (0=top, 1=bottom)
    public private(set) var samplingYRatio: CGFloat

    /// Total observation count
    public private(set) var observationCount: Int = 0
    /// Consecutive frames observed
    public private(set) var consecutiveObservationCount: Int = 0
    /// Consecutive frames missed
    public private(set) var missedFrameCount: Int = 0
    /// Timestamp of last observation
    public private(set) var lastSeenTime: Date

    // MARK: - Configuration thresholds
    /// Frames to confirm a candidate
    public var confirmationThreshold: Int = 3
    /// Missed frames to become stale
    public var staleThreshold: Int = 15
    /// Missed frames to become lost
    public var lostThreshold: Int = 90

    public init(
        classLabel: String,
        worldPosition: SIMD3<Float>,
        estimatedSize: EstimatedSize,
        confidence: Float,
        samplingYRatio: CGFloat = 0.5
    ) {
        self.id = UUID()
        self.classLabel = classLabel
        self.state = .candidate
        self.worldPosition = worldPosition
        self.estimatedSize = estimatedSize
        self.confidenceMean = confidence
        self.samplingYRatio = samplingYRatio
        self.lastSeenTime = Date()
    }

    // MARK: - EMA Updates

    /// Update with a new observation using EMA smoothing.
    public func updateWith(
        observation: Detection3D,
        positionAlpha: Float = 0.15,
        sizeAlpha: Float = 0.15,
        confidenceAlpha: Float = 0.15
    ) {
        // EMA position
        worldPosition = worldPosition * (1 - positionAlpha) + observation.worldPosition * positionAlpha
        // EMA size
        estimatedSize = estimatedSize.blended(with: observation.estimatedSize, alpha: sizeAlpha)
        // EMA confidence
        confidenceMean = confidenceMean * (1 - confidenceAlpha) + observation.detectionConfidence * confidenceAlpha
        // Update samplingYRatio
        samplingYRatio = samplingYRatio * (1 - CGFloat(positionAlpha)) + observation.samplingYRatio * CGFloat(positionAlpha)

        observationCount += 1
        consecutiveObservationCount += 1
        missedFrameCount = 0
        lastSeenTime = Date()

        // Promote candidate to confirmed
        if state == .candidate && consecutiveObservationCount >= confirmationThreshold {
            state = .confirmed
        }
        // Recapture stale/lost back to confirmed
        if state == .stale || state == .lost {
            state = .confirmed
        }
    }

    /// Advance lifecycle when the object was not observed this frame.
    public func markMissed() {
        consecutiveObservationCount = 0
        missedFrameCount += 1

        switch state {
        case .candidate:
            if missedFrameCount >= confirmationThreshold {
                state = .lost
            }
        case .confirmed:
            if missedFrameCount >= staleThreshold {
                state = .stale
            }
        case .stale:
            if missedFrameCount >= lostThreshold {
                state = .lost
            }
        case .lost:
            break
        }
    }

    /// Distance to another 3D point.
    public func distance(to point: SIMD3<Float>) -> Float {
        simd_distance(worldPosition, point)
    }
}
