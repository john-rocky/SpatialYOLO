import ARKit
import Combine
import simd

/// Main orchestrator for the SpatialYOLO pipeline.
/// Fuses YOLO 2D detections with ARKit LiDAR depth to produce tracked 3D objects.
@MainActor
public final class SpatialPipeline: ObservableObject {

    // MARK: - Published State

    /// Currently tracked objects (confirmed, stale, and candidate).
    @Published public private(set) var trackedObjects: [TrackedObject] = []

    /// Camera state snapshot from the latest processed frame.
    @Published public private(set) var cameraState: CameraState?

    // MARK: - Components

    private let depthProvider: ARDepthProvider
    private let detection3DFactory: Detection3DFactory
    private let backProjectionMatcher: BackProjectionMatcher
    private let slotManager: SlotManager
    private let config: SpatialYOLOConfig

    /// Optional built-in detector (Mode A)
    private var detector: ObjectDetector?
    private let session: ARSession

    // MARK: - Init

    /// Mode A: Built-in detector — pipeline runs YOLO internally per frame.
    public init(session: ARSession, detector: ObjectDetector, config: SpatialYOLOConfig = .default) {
        self.session = session
        self.detector = detector
        self.config = config
        self.depthProvider = ARDepthProvider()
        self.detection3DFactory = Detection3DFactory(config: config)
        self.backProjectionMatcher = BackProjectionMatcher(config: config)
        self.slotManager = SlotManager(config: config)
    }

    /// Mode B: External detections — consumer provides Detection2D each frame.
    public init(session: ARSession, config: SpatialYOLOConfig = .default) {
        self.session = session
        self.detector = nil
        self.config = config
        self.depthProvider = ARDepthProvider()
        self.detection3DFactory = Detection3DFactory(config: config)
        self.backProjectionMatcher = BackProjectionMatcher(config: config)
        self.slotManager = SlotManager(config: config)
    }

    // MARK: - Per-Frame Update

    /// Process a new ARFrame with external 2D detections (Mode B).
    public func update(frame: ARFrame, detections: [Detection2D]) {
        // 1. Update depth provider
        depthProvider.updateFrame(frame)

        // 2. Lift 2D detections to 3D
        let detections3D = detection3DFactory.createDetections3D(
            from: detections,
            depthProvider: depthProvider
        )

        // 3. Create camera state for projections
        let camera = CameraState(camera: frame.camera)

        // 4. Back-project existing slots → match with incoming detections
        let matchResult = backProjectionMatcher.match(
            objects: slotManager.objects,
            detections: detections3D,
            camera: camera
        )

        // 5. Update matched slots (EMA position/size)
        for (objectID, detection) in matchResult.matched {
            slotManager.updateObject(id: objectID, with: detection)
        }

        // 6. Attempt 3D recapture for stale slots with unmatched detections
        var unmatchedDetections = matchResult.unmatchedDetections
        let recapturedIDs = Set(slotManager.attemptRecapture(unmatchedDetections: &unmatchedDetections))

        // 7. Create new candidates for remaining unmatched detections
        slotManager.createCandidates(from: unmatchedDetections)

        // 8. Advance lifecycle for ALL non-lost objects not matched or recaptured
        let matchedIDs = Set(matchResult.matched.map { $0.objectID })
        let allMissedIDs = slotManager.objects
            .filter { $0.state != .lost && !matchedIDs.contains($0.id) && !recapturedIDs.contains($0.id) }
            .map { $0.id }
        slotManager.advanceLifecycle(missedIDs: allMissedIDs)

        // 8b. Purge lost objects to prevent unbounded array growth
        slotManager.purgeLostObjects()

        // 9. Publish updated state
        cameraState = camera
        trackedObjects = slotManager.visibleObjects
    }

    /// Process a new ARFrame using the built-in detector (Mode A).
    /// Runs YOLO inference on the frame's capturedImage.
    public func update(frame: ARFrame) {
        guard let detector = detector else { return }
        let detections = detector.detect(
            pixelBuffer: frame.capturedImage,
            timestamp: frame.timestamp
        )
        update(frame: frame, detections: detections)
    }

    // MARK: - Accessors

    /// All tracked objects including lost ones.
    public var allObjects: [TrackedObject] {
        slotManager.objects
    }

    /// Get the depth provider for external use (e.g., custom projections).
    public var currentDepthProvider: ARDepthProvider {
        depthProvider
    }
}
