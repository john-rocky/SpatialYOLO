import SwiftUI
import ARKit

/// SF scan-style overlay that draws 3D bounding box corner brackets and edges
/// for tracked objects. Replaces DetectionBoxOverlayView and GhostBoxView.
struct ScanOverlayView: View {
    let objects: [TrackedObject]
    let camera: CameraState?

    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size

            if let cam = camera {
                let cameraPos = SIMD3<Float>(
                    cam.transform.columns.3.x,
                    cam.transform.columns.3.y,
                    cam.transform.columns.3.z
                )

                // Aspect-fill transform: camera image → screen pixels
                // Camera is landscape (e.g. 1920x1440), displayed in portrait
                let fillTransform = AspectFillTransform(
                    cameraResolution: cam.imageResolution,
                    screenSize: screenSize
                )

                Canvas { context, size in
                    for object in objects {
                        guard object.state != .lost else { continue }

                        guard let corners = cam.projectBoxCorners(
                            center: object.worldPosition,
                            size: object.estimatedSize,
                            samplingYRatio: object.samplingYRatio,
                            cameraPosition: cameraPos
                        ) else { continue }

                        let color = stateColor(object.state)
                        let frontPoints = corners.front.map { fillTransform.toScreen($0) }
                        let backPoints = corners.back.map { fillTransform.toScreen($0) }

                        // Draw depth edges (back-to-front connecting lines)
                        drawDepthEdges(
                            context: &context,
                            front: frontPoints,
                            back: backPoints,
                            color: color
                        )

                        // Draw back corner brackets (dimmer)
                        drawCornerBrackets(
                            context: &context,
                            points: backPoints,
                            color: color,
                            opacity: 0.3,
                            lineWidth: 1.0,
                            size: size
                        )

                        // Draw front corner brackets (bright)
                        drawCornerBrackets(
                            context: &context,
                            points: frontPoints,
                            color: color,
                            opacity: 0.9,
                            lineWidth: 2.0,
                            size: size
                        )
                    }
                }
                .frame(width: screenSize.width, height: screenSize.height)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    /// Draw L-shaped corner brackets at each of the 4 corner points.
    /// Points order: top-left, top-right, bottom-right, bottom-left.
    private func drawCornerBrackets(
        context: inout GraphicsContext,
        points: [CGPoint],
        color: Color,
        opacity: Double,
        lineWidth: CGFloat,
        size: CGSize
    ) {
        guard points.count == 4 else { return }

        // Compute bracket length from box size (fraction of shortest side)
        let dx = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
        let dy = hypot(points[3].x - points[0].x, points[3].y - points[0].y)
        let bracketLen = max(min(dx, dy) * 0.25, 6)

        // Direction vectors for each corner's two edges
        let cornerDirs: [(Int, Int, Int)] = [
            (0, 1, 3),  // top-left → toward top-right, toward bottom-left
            (1, 0, 2),  // top-right → toward top-left, toward bottom-right
            (2, 3, 1),  // bottom-right → toward bottom-left, toward top-right
            (3, 2, 0),  // bottom-left → toward bottom-right, toward top-left
        ]

        var bracketPath = Path()

        for (corner, neighborA, neighborB) in cornerDirs {
            let p = points[corner]
            let dirA = unitDirection(from: p, to: points[neighborA])
            let dirB = unitDirection(from: p, to: points[neighborB])

            let endA = CGPoint(x: p.x + dirA.x * bracketLen, y: p.y + dirA.y * bracketLen)
            let endB = CGPoint(x: p.x + dirB.x * bracketLen, y: p.y + dirB.y * bracketLen)

            bracketPath.move(to: endA)
            bracketPath.addLine(to: p)
            bracketPath.addLine(to: endB)
        }

        // Glow layer
        var glowContext = context
        glowContext.addFilter(.shadow(color: color.opacity(opacity * 0.6), radius: 4))
        glowContext.stroke(
            bracketPath,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )

        // Main stroke
        context.stroke(
            bracketPath,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    /// Draw thin connecting lines between front and back corners.
    private func drawDepthEdges(
        context: inout GraphicsContext,
        front: [CGPoint],
        back: [CGPoint],
        color: Color
    ) {
        guard front.count == 4, back.count == 4 else { return }

        var edgePath = Path()
        for i in 0..<4 {
            edgePath.move(to: front[i])
            edgePath.addLine(to: back[i])
        }

        // Glow
        var glowContext = context
        glowContext.addFilter(.shadow(color: color.opacity(0.3), radius: 3))
        glowContext.stroke(
            edgePath,
            with: .color(color.opacity(0.25)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
        )

        // Main stroke
        context.stroke(
            edgePath,
            with: .color(color.opacity(0.25)),
            style: StrokeStyle(lineWidth: 1.0, dash: [4, 4], dashPhase: 0)
        )
    }

    // MARK: - Helpers

    private func unitDirection(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0.001 else { return .zero }
        return CGPoint(x: dx / len, y: dy / len)
    }

    private func stateColor(_ state: SlotState) -> Color {
        switch state {
        case .confirmed: return Color(red: 0, green: 0.898, blue: 1.0)   // #00E5FF cyan
        case .stale:     return Color.orange
        case .candidate: return Color.gray
        case .lost:      return Color.gray
        }
    }
}

// MARK: - Aspect Fill Transform

/// Converts normalized portrait coordinates (0-1) to screen pixels,
/// accounting for aspect-fill display of the camera feed.
/// Camera image is landscape (e.g. 1920x1440) displayed in portrait with aspect fill.
private struct AspectFillTransform {
    let offsetX: CGFloat
    let offsetY: CGFloat
    let scaledWidth: CGFloat
    let scaledHeight: CGFloat

    init(cameraResolution: CGSize, screenSize: CGSize) {
        // Camera is landscape; rotated portrait dimensions
        let rotatedW = cameraResolution.height
        let rotatedH = cameraResolution.width

        guard rotatedW > 0, rotatedH > 0 else {
            // Fallback: simple 1:1 mapping
            offsetX = 0
            offsetY = 0
            scaledWidth = screenSize.width
            scaledHeight = screenSize.height
            return
        }

        let scaleX = screenSize.width / rotatedW
        let scaleY = screenSize.height / rotatedH
        let scale = max(scaleX, scaleY)  // aspect fill

        scaledWidth = rotatedW * scale
        scaledHeight = rotatedH * scale
        offsetX = (screenSize.width - scaledWidth) / 2
        offsetY = (screenSize.height - scaledHeight) / 2
    }

    /// Convert a normalized portrait point (0-1) to screen pixels.
    func toScreen(_ normalized: CGPoint) -> CGPoint {
        CGPoint(
            x: offsetX + normalized.x * scaledWidth,
            y: offsetY + normalized.y * scaledHeight
        )
    }
}
