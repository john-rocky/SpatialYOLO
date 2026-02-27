import Foundation
import RealityKit
import simd

/// Manages RealityKit 3D billboard entities that float above tracked objects in world space.
final class BillboardEntityManager {

    struct BillboardEntry {
        let entity: ModelEntity
        var cachedState: SlotState
        var cachedDistanceBucket: Int   // distance in 50cm buckets
        var cachedSizeW: Int            // width in 5cm buckets
        var cachedSizeH: Int            // height in 5cm buckets
    }

    let rootAnchor: AnchorEntity
    private var entries: [UUID: BillboardEntry] = [:]
    private let planeMesh: MeshResource
    private let renderer: BillboardTextureRenderer

    /// Billboard physical size in meters (width x height).
    private let billboardWidth: Float = 0.12
    private let billboardHeight: Float = 0.06

    init() {
        self.rootAnchor = AnchorEntity(world: .zero)
        self.planeMesh = .generatePlane(width: 0.12, height: 0.06)
        self.renderer = BillboardTextureRenderer()
    }

    /// Update all billboard entities for the current frame.
    /// - Parameters:
    ///   - objects: Currently tracked objects
    ///   - cameraState: Current camera state for orientation and distance
    func update(objects: [TrackedObject], cameraState: CameraState?) {
        guard let cam = cameraState else { return }

        let cameraPos = SIMD3<Float>(
            cam.transform.columns.3.x,
            cam.transform.columns.3.y,
            cam.transform.columns.3.z
        )

        let activeIDs = Set(objects.map { $0.id })

        // Remove entities for objects no longer tracked
        for (id, entry) in entries where !activeIDs.contains(id) {
            entry.entity.removeFromParent()
            entries.removeValue(forKey: id)
        }

        // Create or update entities for each tracked object
        for object in objects {
            // Skip lost objects
            guard object.state != .lost else {
                if let entry = entries[object.id] {
                    entry.entity.removeFromParent()
                    entries.removeValue(forKey: object.id)
                }
                continue
            }

            let entityPos = object.worldPosition + SIMD3<Float>(
                0,
                object.estimatedSize.height * 0.5 + 0.08,
                0
            )

            let distance = cam.distanceToCamera(object.worldPosition)
            let distanceBucket = Int(distance * 2)  // 50cm buckets
            let sizeW = Int(object.estimatedSize.width * 20)   // 5cm buckets
            let sizeH = Int(object.estimatedSize.height * 20)  // 5cm buckets

            if var entry = entries[object.id] {
                // Update position
                entry.entity.position = entityPos

                // Update orientation to face camera (cylindrical billboard)
                entry.entity.orientation = billboardOrientation(
                    entityPos: entityPos,
                    cameraPos: cameraPos
                )

                // Regenerate texture only when visual data changes
                let needsTextureUpdate =
                    entry.cachedState != object.state ||
                    entry.cachedDistanceBucket != distanceBucket ||
                    entry.cachedSizeW != sizeW ||
                    entry.cachedSizeH != sizeH

                if needsTextureUpdate {
                    if let material = makeMaterial(
                        classLabel: object.classLabel,
                        size: object.estimatedSize,
                        distance: distance,
                        state: object.state
                    ) {
                        entry.entity.model?.materials = [material]
                    }
                    entry.cachedState = object.state
                    entry.cachedDistanceBucket = distanceBucket
                    entry.cachedSizeW = sizeW
                    entry.cachedSizeH = sizeH
                }

                entries[object.id] = entry
            } else {
                // Create new entity
                let entity = ModelEntity(mesh: planeMesh)
                entity.position = entityPos
                entity.orientation = billboardOrientation(
                    entityPos: entityPos,
                    cameraPos: cameraPos
                )

                if let material = makeMaterial(
                    classLabel: object.classLabel,
                    size: object.estimatedSize,
                    distance: distance,
                    state: object.state
                ) {
                    entity.model?.materials = [material]
                }

                rootAnchor.addChild(entity)
                entries[object.id] = BillboardEntry(
                    entity: entity,
                    cachedState: object.state,
                    cachedDistanceBucket: distanceBucket,
                    cachedSizeW: sizeW,
                    cachedSizeH: sizeH
                )
            }
        }
    }

    // MARK: - Private

    /// Compute billboard orientation: faces camera yaw, stays upright.
    private func billboardOrientation(
        entityPos: SIMD3<Float>,
        cameraPos: SIMD3<Float>
    ) -> simd_quatf {
        let direction = cameraPos - entityPos
        let yaw = atan2(direction.x, direction.z)
        return simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }

    /// Create an UnlitMaterial with the rendered billboard texture.
    private func makeMaterial(
        classLabel: String,
        size: EstimatedSize,
        distance: Float,
        state: SlotState
    ) -> UnlitMaterial? {
        guard let cgImage = renderer.render(
            classLabel: classLabel,
            size: size,
            distance: distance,
            state: state
        ) else { return nil }

        do {
            let texture = try TextureResource.generate(
                from: cgImage,
                options: .init(semantic: .color)
            )
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: 1.0)
            return material
        } catch {
            return nil
        }
    }
}
