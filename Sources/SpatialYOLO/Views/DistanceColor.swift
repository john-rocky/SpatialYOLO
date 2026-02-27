import UIKit
import SwiftUI

/// Shared color utility for distance-based visual feedback.
/// Piecewise-linear interpolation: near (red-orange) → mid (green) → far (cyan).
enum DistanceColor {

    /// UIColor for billboard rendering (confirmed objects only).
    static func uiColor(
        distance: Float,
        near: Float,
        mid: Float,
        far: Float
    ) -> UIColor {
        let (r, g, b) = interpolateRGB(distance: distance, near: near, mid: mid, far: far)
        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
    }

    /// SwiftUI Color for overlay rendering (confirmed objects only).
    static func color(
        distance: Float,
        near: Float,
        mid: Float,
        far: Float
    ) -> Color {
        let (r, g, b) = interpolateRGB(distance: distance, near: near, mid: mid, far: far)
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }

    /// Proximity bar fill fraction (1.0 = full/near, 0.0 = empty/far).
    static func proximityFill(distance: Float, maxDistance: Float) -> CGFloat {
        guard maxDistance > 0 else { return 0 }
        let clamped = min(max(distance, 0), maxDistance)
        return CGFloat(1.0 - clamped / maxDistance)
    }

    // MARK: - Private

    /// Piecewise-linear RGB interpolation:
    ///   distance <= near  → red-orange (1.0, 0.35, 0.0)
    ///   distance == mid   → green      (0.0, 0.85, 0.2)
    ///   distance >= far   → cyan       (0.0, 0.898, 1.0) — matches #00E5FF
    private static func interpolateRGB(
        distance: Float,
        near: Float,
        mid: Float,
        far: Float
    ) -> (Float, Float, Float) {
        // Near color: red-orange
        let nearR: Float = 1.0, nearG: Float = 0.35, nearB: Float = 0.0
        // Mid color: green
        let midR: Float = 0.0, midG: Float = 0.85, midB: Float = 0.2
        // Far color: cyan (#00E5FF)
        let farR: Float = 0.0, farG: Float = 0.898, farB: Float = 1.0

        if distance <= near {
            return (nearR, nearG, nearB)
        } else if distance <= mid {
            let t = (distance - near) / (mid - near)
            return (
                nearR + (midR - nearR) * t,
                nearG + (midG - nearG) * t,
                nearB + (midB - nearB) * t
            )
        } else if distance <= far {
            let t = (distance - mid) / (far - mid)
            return (
                midR + (farR - midR) * t,
                midG + (farG - midG) * t,
                midB + (farB - midB) * t
            )
        } else {
            return (farR, farG, farB)
        }
    }
}
