import UIKit

/// Renders billboard label content to a CGImage for use as a RealityKit entity texture.
/// Vision Pro glassmorphism style: dark glass background with luminous accent.
final class BillboardTextureRenderer {

    // Texture dimensions (points). Rendered at 3x scale → 840x300 pixels.
    private let textureWidth: CGFloat = 280
    private let textureHeight: CGFloat = 100
    private let scale: CGFloat = 3

    private let renderer: UIGraphicsImageRenderer

    init() {
        let size = CGSize(width: 280, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        self.renderer = UIGraphicsImageRenderer(size: size, format: format)
    }

    /// Render a billboard label to a CGImage.
    /// - Parameters:
    ///   - classLabel: Object class name
    ///   - size: Estimated physical size
    ///   - distance: Distance from camera in meters
    ///   - state: Current tracking state (determines accent color)
    /// - Returns: Rendered CGImage, or nil on failure
    func render(
        classLabel: String,
        size: EstimatedSize,
        distance: Float,
        state: SlotState
    ) -> CGImage? {
        let image = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: textureWidth, height: textureHeight)
            let context = ctx.cgContext
            let accentColor = stateUIColor(state)

            let cornerRadius: CGFloat = 10
            let insetRect = rect.insetBy(dx: 1, dy: 1)
            let bgPath = UIBezierPath(roundedRect: insetRect, cornerRadius: cornerRadius)

            // Dark glass background
            let bgColor = UIColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 0.82)
            context.setFillColor(bgColor.cgColor)
            bgPath.fill()

            // Luminous border
            context.setStrokeColor(accentColor.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(1.5)
            bgPath.stroke()

            // Top accent bar
            let accentBarRect = CGRect(x: insetRect.minX + cornerRadius,
                                       y: insetRect.minY,
                                       width: insetRect.width - cornerRadius * 2,
                                       height: 3)
            context.setFillColor(accentColor.withAlphaComponent(0.85).cgColor)
            context.fill(accentBarRect)

            // Text styles
            let titleFont = UIFont.systemFont(ofSize: 26, weight: .bold)
            let detailFont = UIFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
            let centerStyle = NSMutableParagraphStyle()
            centerStyle.alignment = .center

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: centerStyle
            ]
            let detailAttrs: [NSAttributedString.Key: Any] = [
                .font: detailFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .paragraphStyle: centerStyle
            ]

            // Class label
            let titleRect = CGRect(x: 12, y: 14, width: textureWidth - 24, height: 34)
            (classLabel as NSString).draw(in: titleRect, withAttributes: titleAttrs)

            // Combined info line: distance · WxHcm
            let infoText = "\(formatDistance(distance)) · \(formatSize(size))"
            let infoRect = CGRect(x: 12, y: 54, width: textureWidth - 24, height: 26)
            (infoText as NSString).draw(in: infoRect, withAttributes: detailAttrs)
        }
        return image.cgImage
    }

    private func stateUIColor(_ state: SlotState) -> UIColor {
        switch state {
        case .confirmed: return UIColor(red: 0, green: 0.898, blue: 1.0, alpha: 1.0)  // #00E5FF
        case .stale:     return .systemOrange
        case .candidate: return .systemGray
        case .lost:      return .systemGray
        }
    }

    private func formatSize(_ size: EstimatedSize) -> String {
        let wCm = Int(round(size.width * 20)) * 5
        let hCm = Int(round(size.height * 20)) * 5
        return "\(wCm)×\(hCm)cm"
    }

    private func formatDistance(_ distance: Float) -> String {
        let cm = Int(round(distance * 100))  // 1cm precision
        if cm < 100 {
            return "\(cm)cm"
        } else {
            return String(format: "%.2fm", Float(cm) / 100)
        }
    }
}
