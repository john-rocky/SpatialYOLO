import ARKit
import SpatialYOLO

@MainActor
final class ARSessionManager: NSObject, ObservableObject {

    enum State {
        case idle
        case loading
        case running
        case error(String)
    }

    @Published private(set) var state: State = .idle

    let session = ARSession()
    private(set) var pipeline: SpatialPipeline?

    func start() async {
        state = .loading

        // Check LiDAR availability
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) else {
            state = .error("This device does not support LiDAR depth sensing.")
            return
        }

        // Load YOLO model
        let detector = YOLODetector(modelName: "yolo26n")
        do {
            try await detector.loadModel()
        } catch {
            state = .error("Failed to load YOLO model: \(error.localizedDescription)")
            return
        }

        // Create pipeline (Mode A: built-in detector)
        pipeline = SpatialPipeline(session: session, detector: detector)

        // Configure and run AR session
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.smoothedSceneDepth)
        session.delegate = self
        session.run(config)

        state = .running
    }
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            pipeline?.update(frame: frame)
        }
    }
}
