import SwiftUI
import ARKit

/// SF scan-style overlay that draws 3D bounding box corner brackets and edges
/// for tracked objects. Replaces DetectionBoxOverlayView and GhostBoxView.
struct ScanOverlayView: View {
    let objects: [TrackedObject]
    let camera: CameraState?
    var config: SpatialYOLOConfig = .default

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
                    // Sort objects by distance for glow LOD
                    let sortedObjects = objects
                        .filter { $0.state != .lost }
                        .sorted { cam.distanceToCamera($0.worldPosition) < cam.distanceToCamera($1.worldPosition) }

                    for (index, object) in sortedObjects.enumerated() {
                        guard let corners = cam.projectBoxCorners(
                            center: object.worldPosition,
                            size: object.estimatedSize,
                            samplingYRatio: object.samplingYRatio,
                            cameraPosition: cameraPos
                        ) else { continue }

                        let distance = cam.distanceToCamera(object.worldPosition)
                        let useGlow = index < config.maxGlowObjects
                        let color = accentColor(
                            state: object.state,
                            distance: distance
                        )

                        // Proximity factor: 1.0 at near, 0.0 at far
                        let proximityFactor = object.state == .confirmed
                            ? DistanceColor.proximityFill(
                                distance: distance,
                                maxDistance: config.distanceFar
                            )
                            : 0.0

                        // Scale styling with proximity
                        let bracketFrontLineWidth: CGFloat = 2.0 + 2.0 * proximityFactor
                        let bracketFrontOpacity: Double = 0.7 + 0.3 * proximityFactor
                        let bracketBackLineWidth: CGFloat = 1.0 + 1.0 * proximityFactor
                        let bracketBackOpacity: Double = 0.2 + 0.2 * proximityFactor

                        let wireFrontLineWidth: CGFloat = 1.6 + 1.6 * proximityFactor
                        let wireFrontOpacity: Double = 0.56 + 0.24 * proximityFactor
                        let wireBackLineWidth: CGFloat = 0.8 + 0.8 * proximityFactor
                        let wireBackOpacity: Double = 0.14 + 0.14 * proximityFactor

                        let frontPoints = corners.front.map { fillTransform.toScreen($0) }
                        let backPoints = corners.back.map { fillTransform.toScreen($0) }

                        // Layer 1: Semi-transparent face fills
                        drawFaceFills(
                            context: &context,
                            front: frontPoints,
                            back: backPoints,
                            color: color,
                            proximityFactor: proximityFactor
                        )

                        // Layer 1.5: Bottom face AO shadow
                        drawBottomAO(
                            context: &context,
                            front: frontPoints,
                            back: backPoints,
                            proximityFactor: proximityFactor
                        )

                        // Layer 2: Back face wireframe (dashed)
                        drawWireframeFaceEdges(
                            context: &context,
                            points: backPoints,
                            color: color,
                            opacity: wireBackOpacity,
                            lineWidth: wireBackLineWidth,
                            useGlow: useGlow,
                            dashPattern: [6, 4]
                        )

                        // Layer 3: Depth edges (solid with gradient)
                        drawDepthEdges(
                            context: &context,
                            front: frontPoints,
                            back: backPoints,
                            color: color,
                            frontOpacity: bracketFrontOpacity,
                            frontLineWidth: bracketFrontLineWidth,
                            useGlow: useGlow
                        )

                        // Layer 4: Front face wireframe
                        drawWireframeFaceEdges(
                            context: &context,
                            points: frontPoints,
                            color: color,
                            opacity: wireFrontOpacity,
                            lineWidth: wireFrontLineWidth,
                            useGlow: useGlow
                        )

                        // Layer 5: Corner bracket accents (back smaller, then front)
                        drawCornerBrackets(
                            context: &context,
                            points: backPoints,
                            color: color,
                            opacity: bracketBackOpacity,
                            lineWidth: bracketBackLineWidth,
                            size: size,
                            useGlow: useGlow,
                            bracketScale: 0.7
                        )
                        drawCornerBrackets(
                            context: &context,
                            points: frontPoints,
                            color: color,
                            opacity: bracketFrontOpacity,
                            lineWidth: bracketFrontLineWidth,
                            size: size,
                            useGlow: useGlow
                        )
                    }
                }
                .frame(width: screenSize.width, height: screenSize.height)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    /// Draw semi-transparent face fills for visible faces of the 3D box.
    /// Uses signed-area test to determine which faces are visible.
    /// Per-face directional shading simulates overhead lighting.
    private func drawFaceFills(
        context: inout GraphicsContext,
        front: [CGPoint],
        back: [CGPoint],
        color: Color,
        proximityFactor: Double
    ) {
        guard front.count == 4, back.count == 4 else { return }

        // Base opacity scales with proximity (closer = more visible)
        let pf = proximityFactor
        let baseOpacity = 0.08 + 0.10 * pf

        // Directional shading multipliers (simulated overhead + camera-facing light)
        // Front: 1.0 (facing camera, brightest)
        // Top: 0.85 (overhead ambient light)
        // Left/Right sides: 0.5 (side-lit, darker)
        // Bottom: 0.25 (in shadow)
        // Back: 0.2 (away from camera)
        let faces: [([CGPoint], CGFloat)] = [
            ([front[0], front[1], front[2], front[3]], 1.0),
            ([back[0], back[3], back[2], back[1]], 0.2),
            ([front[0], front[1], back[1], back[0]], 0.85),
            ([front[3], back[3], back[2], front[2]], 0.25),
            ([front[0], back[0], back[3], front[3]], 0.5),
            ([front[1], front[2], back[2], back[1]], 0.5),
        ]

        for (pts, multiplier) in faces {
            let area = signedArea(pts)
            guard area < 0 else { continue }

            // Scale shading by projected area ratio for dynamic adjustment
            let absArea = abs(area)
            let facingFactor = min(absArea / 1000, 1.0)
            let adjustedMultiplier = Double(multiplier) * (0.7 + 0.3 * facingFactor)

            var path = Path()
            path.move(to: pts[0])
            for i in 1..<pts.count {
                path.addLine(to: pts[i])
            }
            path.closeSubpath()

            let opacity = baseOpacity * adjustedMultiplier
            context.fill(path, with: .color(color.opacity(opacity)))
        }
    }

    /// Draw a subtle black AO shadow on the bottom face to ground the box visually.
    private func drawBottomAO(
        context: inout GraphicsContext,
        front: [CGPoint],
        back: [CGPoint],
        proximityFactor: Double
    ) {
        guard front.count == 4, back.count == 4 else { return }

        // Bottom face: front[3], back[3], back[2], front[2]
        let bottomPts = [front[3], back[3], back[2], front[2]]

        // Only draw if front-facing
        let area = signedArea(bottomPts)
        guard area < 0 else { return }

        var path = Path()
        path.move(to: bottomPts[0])
        for i in 1..<bottomPts.count {
            path.addLine(to: bottomPts[i])
        }
        path.closeSubpath()

        let aoOpacity = 0.06 + 0.08 * proximityFactor
        context.fill(path, with: .color(Color.black.opacity(aoOpacity)))
    }

    /// Draw full wireframe edges for a face (4 sides, not just corner brackets).
    private func drawWireframeFaceEdges(
        context: inout GraphicsContext,
        points: [CGPoint],
        color: Color,
        opacity: Double,
        lineWidth: CGFloat,
        glowRadius: CGFloat = 3,
        useGlow: Bool = true,
        dashPattern: [CGFloat]? = nil
    ) {
        guard points.count == 4 else { return }

        var edgePath = Path()
        for i in 0..<4 {
            edgePath.move(to: points[i])
            edgePath.addLine(to: points[(i + 1) % 4])
        }

        let style = StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: dashPattern ?? []
        )

        // Glow layer (only for nearby objects)
        if useGlow {
            var glowContext = context
            glowContext.addFilter(.shadow(color: color.opacity(opacity * 0.5), radius: glowRadius))
            glowContext.stroke(
                edgePath,
                with: .color(color.opacity(opacity)),
                style: style
            )
        }

        // Main stroke
        context.stroke(
            edgePath,
            with: .color(color.opacity(opacity)),
            style: style
        )
    }

    /// Draw L-shaped corner brackets at each of the 4 corner points.
    /// Points order: top-left, top-right, bottom-right, bottom-left.
    private func drawCornerBrackets(
        context: inout GraphicsContext,
        points: [CGPoint],
        color: Color,
        opacity: Double,
        lineWidth: CGFloat,
        size: CGSize,
        useGlow: Bool = true,
        bracketScale: CGFloat = 1.0
    ) {
        guard points.count == 4 else { return }

        // Compute bracket length from box size (fraction of shortest side)
        let dx = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
        let dy = hypot(points[3].x - points[0].x, points[3].y - points[0].y)
        let bracketLen = max(min(dx, dy) * 0.25 * bracketScale, 6)

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

        // Glow layer (only for nearby objects)
        if useGlow {
            var glowContext = context
            glowContext.addFilter(.shadow(color: color.opacity(opacity * 0.6), radius: 4))
            glowContext.stroke(
                bracketPath,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }

        // Main stroke
        context.stroke(
            bracketPath,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    /// Draw solid connecting lines between front and back corners with gradient opacity.
    /// Each edge is split into two halves with tapered line widths for perspective.
    private func drawDepthEdges(
        context: inout GraphicsContext,
        front: [CGPoint],
        back: [CGPoint],
        color: Color,
        frontOpacity: Double,
        frontLineWidth: CGFloat,
        useGlow: Bool = true
    ) {
        guard front.count == 4, back.count == 4 else { return }

        let frontEdgeWidth = frontLineWidth * 0.7
        let backEdgeWidth = frontLineWidth * 0.35
        let nearOpacity = frontOpacity * 0.6
        let farOpacity = frontOpacity * 0.8 * 0.6

        for i in 0..<4 {
            let f = front[i]
            let b = back[i]
            let mid = CGPoint(x: (f.x + b.x) / 2, y: (f.y + b.y) / 2)

            // Front half (brighter, thicker)
            var frontPath = Path()
            frontPath.move(to: f)
            frontPath.addLine(to: mid)

            if useGlow {
                var glowCtx1 = context
                glowCtx1.addFilter(.shadow(color: color.opacity(nearOpacity * 0.5), radius: 2))
                glowCtx1.stroke(
                    frontPath,
                    with: .color(color.opacity(nearOpacity)),
                    style: StrokeStyle(lineWidth: frontEdgeWidth, lineCap: .round)
                )
            }
            context.stroke(
                frontPath,
                with: .color(color.opacity(nearOpacity)),
                style: StrokeStyle(lineWidth: frontEdgeWidth, lineCap: .round)
            )

            // Back half (dimmer, thinner, no glow)
            var backPath = Path()
            backPath.move(to: mid)
            backPath.addLine(to: b)

            context.stroke(
                backPath,
                with: .color(color.opacity(farOpacity)),
                style: StrokeStyle(lineWidth: backEdgeWidth, lineCap: .round)
            )
        }
    }

    // MARK: - Helpers

    private func unitDirection(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0.001 else { return .zero }
        return CGPoint(x: dx / len, y: dy / len)
    }

    /// Signed area of a polygon (positive = CCW, negative = CW).
    /// Used to determine face visibility (front-facing vs back-facing).
    private func signedArea(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count >= 3 else { return 0 }
        var area: CGFloat = 0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            area += pts[i].x * pts[j].y
            area -= pts[j].x * pts[i].y
        }
        return area / 2
    }

    private func accentColor(state: SlotState, distance: Float) -> Color {
        switch state {
        case .confirmed:
            return DistanceColor.color(
                distance: distance,
                near: config.distanceNear,
                mid: config.distanceMid,
                far: config.distanceFar
            )
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
