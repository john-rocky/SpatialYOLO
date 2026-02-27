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
                cameraState: pipeline.cameraState,
                config: pipeline.currentConfig
            )
            .ignoresSafeArea()

            // SF scan-style 3D bounding box overlay
            ScanOverlayView(
                objects: pipeline.trackedObjects,
                camera: pipeline.cameraState,
                config: pipeline.currentConfig
            )
        }
    }
}
