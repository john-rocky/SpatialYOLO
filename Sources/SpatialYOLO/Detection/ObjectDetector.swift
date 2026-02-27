import CoreVideo
import Foundation

/// Protocol for pluggable object detection.
/// Consumers can provide their own detector or use the built-in YOLODetector.
public protocol ObjectDetector: AnyObject {
    /// Run detection on a pixel buffer and return 2D detections.
    func detect(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [Detection2D]
    /// Load the detection model asynchronously.
    func loadModel() async throws
}
