import SwiftUI
import ARKit
import RealityKit

/// UIViewRepresentable wrapping ARView for LiDAR-enabled AR sessions.
/// Also manages 3D billboard entities in world space via BillboardEntityManager.
public struct ARViewContainer: UIViewRepresentable {

    let session: ARSession
    let trackedObjects: [TrackedObject]
    let cameraState: CameraState?

    public init(
        session: ARSession,
        trackedObjects: [TrackedObject] = [],
        cameraState: CameraState? = nil
    ) {
        self.session = session
        self.trackedObjects = trackedObjects
        self.cameraState = cameraState
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = session
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disablePersonOcclusion]

        // Attach billboard root anchor to the scene
        arView.scene.addAnchor(context.coordinator.manager.rootAnchor)

        return arView
    }

    public func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.manager.update(
            objects: trackedObjects,
            cameraState: cameraState
        )
    }

    // MARK: - Coordinator

    public final class Coordinator {
        let manager = BillboardEntityManager()
    }
}
