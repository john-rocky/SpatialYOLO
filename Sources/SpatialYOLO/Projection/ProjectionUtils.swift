import CoreGraphics

/// Utility functions for 2D projection matching.
enum ProjectionUtils {

    /// Calculate Intersection over Union (IoU) between two rectangles.
    static func calculateIoU(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let aArea = a.width * a.height
        let bArea = b.width * b.height
        let unionArea = aArea + bArea - intersectionArea

        guard unionArea > 0 else { return 0 }
        return Float(intersectionArea / unionArea)
    }

    /// Calculate normalized center distance between two rectangles.
    static func centerDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return sqrt(dx * dx + dy * dy)
    }

    /// Check if a rect is at the screen edge (partially off-screen).
    static func isAtScreenEdge(_ rect: CGRect, margin: CGFloat = 0.01) -> Bool {
        rect.minX < margin || rect.minY < margin ||
        rect.maxX > (1 - margin) || rect.maxY > (1 - margin)
    }
}
