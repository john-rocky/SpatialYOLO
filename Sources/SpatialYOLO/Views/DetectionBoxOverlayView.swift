import SwiftUI
import ARKit

/// Overlay that draws bounding boxes for confirmed tracked objects.
struct DetectionBoxOverlayView: View {
    let objects: [TrackedObject]
    let camera: CameraState?

    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size

            ForEach(objects) { object in
                if object.state == .confirmed,
                   let cam = camera,
                   let rect = cam.project3DBoxToScreen(
                       center: object.worldPosition,
                       size: object.estimatedSize,
                       samplingYRatio: object.samplingYRatio
                   ) {
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
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
