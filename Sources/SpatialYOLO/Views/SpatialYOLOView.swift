import SwiftUI
import ARKit

/// Main SwiftUI view combining ARView with detection overlays.
/// Billboard labels are rendered as 3D RealityKit entities in world space.
public struct SpatialYOLOView: View {
    @ObservedObject var pipeline: SpatialPipeline
    let session: ARSession

    public init(pipeline: SpatialPipeline, session: ARSession) {
        self.pipeline = pipeline
        self.session = session
    }

    public var body: some View {
        ZStack {
            ARViewContainer(
                session: session,
                trackedObjects: pipeline.trackedObjects,
                cameraState: pipeline.cameraState
            )
            .ignoresSafeArea()

            // Bounding boxes for confirmed objects
            DetectionBoxOverlayView(
                objects: pipeline.trackedObjects,
                camera: pipeline.cameraState
            )

            // Ghost boxes for stale objects
            GhostBoxView(
                objects: pipeline.trackedObjects,
                camera: pipeline.cameraState
            )
        }
    }
}
