import Foundation

/// Read the placement carried by an imported GarmentCode document. This is an
/// initial arrangement, not a sewing, fitting or drape result. Swift-generated
/// pattern-only documents need an explicit native placement recipe instead.
enum GarmentCodePanelPlacement {
    typealias Vector3 = GarmentCodeCircleDrape.Vector3

    nonisolated enum PlacementError: LocalizedError, Sendable {
        case invalid(String)
        var errorDescription: String? {
            switch self { case let .invalid(reason): return "裁片初始摆放无效：\(reason)" }
        }
    }

    nonisolated struct Transform: Sendable {
        /// A source rotation acts on the already metre-normalized paper mesh;
        /// only the original translation is divided by source units per metre.
        let rotationDegrees: [Double]
        let translationMeters: Vector3
        let waistLevelMeters: Double
        private let sine: Vector3
        private let cosine: Vector3

        init(rotationDegrees: [Double], translation: [Double], unitsInMeter: Double,
             waistLevelCentimeters: Double) throws {
            guard rotationDegrees.count == 3, translation.count == 3,
                  rotationDegrees.allSatisfy(\.isFinite), translation.allSatisfy(\.isFinite),
                  unitsInMeter.isFinite, unitsInMeter > 0,
                  waistLevelCentimeters.isFinite, (0...300).contains(waistLevelCentimeters) else {
                throw PlacementError.invalid("旋转和平移必须各含三个有限数值，并使用有效单位和腰线高度。")
            }
            let radians = rotationDegrees.map { $0 * Double.pi / 180 }
            guard radians.allSatisfy(\.isFinite) else {
                throw PlacementError.invalid("旋转角度超出可计算范围。")
            }
            self.rotationDegrees = rotationDegrees
            translationMeters = .init(x: translation[0] / unitsInMeter,
                                      y: translation[1] / unitsInMeter,
                                      z: translation[2] / unitsInMeter)
            waistLevelMeters = waistLevelCentimeters / 100
            guard translationMeters.isFinite else {
                throw PlacementError.invalid("平移单位换算溢出。")
            }
            sine = .init(x: sin(radians[0]), y: sin(radians[1]), z: sin(radians[2]))
            cosine = .init(x: cos(radians[0]), y: cos(radians[1]), z: cos(radians[2]))
        }

        /// Match the actual upstream meshgen formula Rz * Ry * Rx. Do not
        /// substitute a renderer's Euler convention or the constructor's
        /// similarly named SciPy Euler convention.
        func direction(_ vector: Vector3) throws -> Vector3 {
            guard vector.isFinite else { throw PlacementError.invalid("方向包含非有限数值。") }
            let x = Vector3(x: vector.x,
                            y: cosine.x * vector.y - sine.x * vector.z,
                            z: sine.x * vector.y + cosine.x * vector.z)
            let y = Vector3(x: cosine.y * x.x + sine.y * x.z,
                            y: x.y,
                            z: -sine.y * x.x + cosine.y * x.z)
            let result = Vector3(x: cosine.z * y.x - sine.z * y.y,
                                 y: sine.z * y.x + cosine.z * y.y, z: y.z)
            guard result.isFinite else { throw PlacementError.invalid("旋转后方向溢出。") }
            return result
        }

        func point(_ sourceMeters: Vector3) throws -> Vector3 {
            let result = try direction(sourceMeters) + translationMeters
                - Vector3(x: 0, y: waistLevelMeters, z: 0)
            guard result.isFinite else { throw PlacementError.invalid("摆放后的坐标溢出。") }
            return result
        }
    }

    nonisolated struct PlacedPanel: Sendable {
        let panelID: String
        let positions: [Vector3]
        /// Same rotation as the positions, with the original paper winding.
        /// Translation and the waist-origin shift never affect this direction.
        let fabricNormal: Vector3
    }

    /// The complete imported document must actually carry placement data. A
    /// legitimate panel at the origin can coexist with other placed panels;
    /// an entirely zero/missing transform set cannot masquerade as a native
    /// generated assembly. No fields in the document are changed here.
    @MainActor
    static func importedTransforms(document: GarmentCodePatternFile,
                                   waistLevelCentimeters: Double) throws -> [String: Transform] {
        if case let .object(generator)? = document.properties?["tailorass_generator"],
           case .bool(false)? = generator["includes_3d_placement"] {
            throw PlacementError.invalid("这份原生二维纸样未包含三维摆放，必须先建立对应款式的装配方案。")
        }
        try document.validateForPreview()
        var transforms: [String: Transform] = [:]
        var nonzero = false
        for name in document.pattern.panels.keys.sorted() {
            let panel = document.pattern.panels[name]!
            guard let rotation = panel.rotation, let translation = panel.translation else {
                throw PlacementError.invalid("裁片 \(name) 缺少明确的原始旋转或平移。")
            }
            transforms[name] = try Transform(rotationDegrees: rotation, translation: translation,
                unitsInMeter: document.unitsInMeter, waistLevelCentimeters: waistLevelCentimeters)
            nonzero = nonzero || rotation.contains { $0 != 0 } || translation.contains { $0 != 0 }
        }
        guard nonzero else { throw PlacementError.invalid("整份纸样的三维变换均为零，不能据此确认已有成衣装配。") }
        return transforms
    }

    nonisolated static func place(mesh: GarmentCodePanelMesher.Mesh, transform: Transform,
                                  isCancelled: @Sendable () -> Bool = {false}) throws -> PlacedPanel {
        if isCancelled() { throw CancellationError() }
        guard !mesh.panelID.isEmpty, (3...20_000).contains(mesh.flatPositions.count) else {
            throw PlacementError.invalid("需要有界的真实源裁片网格。")
        }
        var positions: [Vector3] = []
        positions.reserveCapacity(mesh.flatPositions.count)
        for (i, point) in mesh.flatPositions.enumerated() {
            if i % 128 == 0 && isCancelled() { throw CancellationError() }
            guard abs(point.z) < 1e-12 else { throw PlacementError.invalid("源网格必须位于二维纸样平面。") }
            positions.append(try transform.point(point))
        }
        let normal = try transform.direction(.init(x: 0, y: 0, z: mesh.sourceClockwise ? -1 : 1))
        return .init(panelID: mesh.panelID, positions: positions, fabricNormal: normal)
    }
}
