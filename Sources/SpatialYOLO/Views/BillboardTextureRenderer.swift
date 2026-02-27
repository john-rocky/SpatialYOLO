import UIKit

/// Renders billboard label content to a CGImage for use as a RealityKit entity texture.
final class BillboardTextureRenderer {

    // Texture dimensions (points). Rendered at 2x scale → 512x256 pixels.
    private let textureWidth: CGFloat = 256
    private let textureHeight: CGFloat = 128
    private let scale: CGFloat = 2

    private let renderer: UIGraphicsImageRenderer

    init() {
        let size = CGSize(width: 256, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        self.renderer = UIGraphicsImageRenderer(size: size, format: format)
    }

    /// Render a billboard label to a CGImage.
    /// - Parameters:
    ///   - classLabel: Object class name
    ///   - size: Estimated physical size
    ///   - distance: Distance from camera in meters
    ///   - state: Current tracking state (determines background color)
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

            // Background rounded rect
            let bgColor = stateUIColor(state).withAlphaComponent(0.75)
            let cornerRadius: CGFloat = 12
            let bgPath = UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: cornerRadius)
            context.setFillColor(bgColor.cgColor)
            bgPath.fill()

            // Border
            let borderColor = stateUIColor(state)
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(2)
            bgPath.stroke()

            // Text attributes
            let titleFont = UIFont.monospacedSystemFont(ofSize: 24, weight: .bold)
            let detailFont = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            let detailStyle = NSMutableParagraphStyle()
            detailStyle.alignment = .center

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: titleStyle
            ]
            let detailAttrs: [NSAttributedString.Key: Any] = [
                .font: detailFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: detailStyle
            ]

            // Line 1: class label
            let titleRect = CGRect(x: 8, y: 10, width: textureWidth - 16, height: 30)
            (classLabel as NSString).draw(in: titleRect, withAttributes: titleAttrs)

            // Line 2: WxHcm
            let sizeText = formatSize(size)
            let sizeRect = CGRect(x: 8, y: 44, width: textureWidth - 16, height: 26)
            (sizeText as NSString).draw(in: sizeRect, withAttributes: detailAttrs)

            // Line 3: distance
            let distText = formatDistance(distance)
            let distRect = CGRect(x: 8, y: 74, width: textureWidth - 16, height: 26)
            (distText as NSString).draw(in: distRect, withAttributes: detailAttrs)
        }
        return image.cgImage
    }

    private func stateUIColor(_ state: SlotState) -> UIColor {
        switch state {
        case .confirmed: return .systemGreen
        case .stale:     return .systemOrange
        case .candidate: return .systemGray
        case .lost:      return .systemGray
        }
    }

    private func formatSize(_ size: EstimatedSize) -> String {
        let wCm = Int(round(size.width * 20)) * 5
        let hCm = Int(round(size.height * 20)) * 5
        return "\(wCm)x\(hCm)cm"
    }

    private func formatDistance(_ distance: Float) -> String {
        let rounded = round(distance * 2) / 2  // 50cm buckets
        if rounded < 1.0 {
            return String(format: "%.0fcm", rounded * 100)
        } else {
            return String(format: "%.1fm", rounded)
        }
    }
}
