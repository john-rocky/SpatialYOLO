import SwiftUI
import ARKit

/// Overlay that draws dashed bounding boxes for stale tracked objects.
struct GhostBoxView: View {
    let objects: [TrackedObject]
    let camera: CameraState?

    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size

            ForEach(objects) { object in
                if object.state == .stale,
                   let cam = camera,
                   let rect = cam.project3DBoxToScreen(
                       center: object.worldPosition,
                       size: object.estimatedSize,
                       samplingYRatio: object.samplingYRatio
                   ) {
                    Rectangle()
                        .stroke(
                            Color.orange,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .frame(
                            width: rect.width * screenSize.width,
                            height: rect.height * screenSize.height
                        )
                        .position(
                            x: rect.midX * screenSize.width,
                            y: rect.midY * screenSize.height
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
