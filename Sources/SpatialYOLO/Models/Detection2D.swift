import Foundation
import CoreGraphics

/// A 2D object detection from YOLO or another detector.
/// Coordinates are normalized 0-1, top-left origin.
public struct Detection2D: Identifiable, Sendable {
    public let id: UUID
    /// Normalized bounding box (0-1, top-left origin)
    public let boundingBox: CGRect
    /// Class label (e.g., "person", "car")
    public let classLabel: String
    /// Detection confidence (0-1)
    public let confidence: Float
    /// Optional 2D tracker ID for cross-frame association
    public let trackID: Int?

    public init(
        id: UUID = UUID(),
        boundingBox: CGRect,
        classLabel: String,
        confidence: Float,
        trackID: Int? = nil
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.classLabel = classLabel
        self.confidence = confidence
        self.trackID = trackID
    }
}
