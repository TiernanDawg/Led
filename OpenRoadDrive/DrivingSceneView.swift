import RealityKit
import SwiftUI
import UIKit

struct DrivingSceneView: UIViewRepresentable {
    @ObservedObject var drive: DriveSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        context.coordinator.install(in: view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(
            position: drive.worldPosition,
            heading: drive.heading,
            cameraMode: drive.cameraMode,
            roads: drive.roads
        )
    }

    final class Coordinator {
        private let anchor = AnchorEntity(world: .zero)
        private let car = Entity()
        private let camera = PerspectiveCamera()
        private var roadIDs: Set<Int> = []

        func install(in view: ARView) {
            view.scene.addAnchor(anchor)
            camera.camera = PerspectiveCameraComponent(near: 0.05, far: 1500, fieldOfViewInDegrees: 72)
            anchor.addChild(camera)
            makeCar()
            makeLighting()
            makeGround()
        }

        private func makeCar() {
            let blue = SimpleMaterial(color: UIColor(red: 0.10, green: 0.32, blue: 0.78, alpha: 1), isMetallic: true)
            let glass = SimpleMaterial(color: UIColor(red: 0.035, green: 0.075, blue: 0.12, alpha: 1), isMetallic: true)
            let rubber = SimpleMaterial(color: UIColor(white: 0.035, alpha: 1), isMetallic: false)
            let trim = SimpleMaterial(color: UIColor(white: 0.72, alpha: 1), isMetallic: true)
            let white = SimpleMaterial(color: .white, isMetallic: false)

            let chassis = ModelEntity(mesh: .generateBox(size: [1.85, 0.62, 4.05]), materials: [blue])
            chassis.position.y = 0.72
            car.addChild(chassis)

            let hood = ModelEntity(mesh: .generateBox(size: [1.72, 0.18, 1.05]), materials: [blue])
            hood.position = [0, 1.02, 1.38]
            car.addChild(hood)

            let cabin = ModelEntity(mesh: .generateBox(size: [1.48, 0.72, 1.85]), materials: [glass])
            cabin.position = [0, 1.35, -0.05]
            car.addChild(cabin)

            let roof = ModelEntity(mesh: .generateBox(size: [1.52, 0.12, 1.8]), materials: [blue])
            roof.position = [0, 1.75, -0.05]
            car.addChild(roof)

            for x: Float in [-0.91, 0.91] {
                for z: Float in [-1.28, 1.28] {
                    let wheel = ModelEntity(mesh: .generateCylinder(height: 0.24, radius: 0.37), materials: [rubber])
                    wheel.position = [x, 0.42, z]
                    wheel.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                    car.addChild(wheel)
                    let hub = ModelEntity(mesh: .generateCylinder(height: 0.255, radius: 0.15), materials: [trim])
                    hub.position = [x * 1.01, 0.42, z]
                    hub.orientation = wheel.orientation
                    car.addChild(hub)
                }
            }

            for x: Float in [-0.58, 0.58] {
                let lamp = ModelEntity(mesh: .generateBox(size: [0.32, 0.13, 0.06]), materials: [white])
                lamp.position = [x, 0.86, 2.05]
                car.addChild(lamp)
            }

            let dashboard = ModelEntity(mesh: .generateBox(size: [1.65, 0.22, 0.48]), materials: [glass])
            dashboard.position = [0, 0.98, 0.58]
            car.addChild(dashboard)

            let steering = ModelEntity(mesh: .generateCylinder(height: 0.07, radius: 0.31), materials: [rubber])
            steering.position = [0, 1.18, 0.35]
            steering.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            car.addChild(steering)

            anchor.addChild(car)
        }

        private func makeLighting() {
            let light = DirectionalLight()
            light.light.intensity = 15000
            light.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
            anchor.addChild(light)
        }

        private func makeGround() {
            let ground = ModelEntity(
                mesh: .generateBox(size: [2000, 0.15, 2000]),
                materials: [SimpleMaterial(color: UIColor(red: 0.20, green: 0.29, blue: 0.18, alpha: 1), isMetallic: false)]
            )
            ground.position.y = -0.16
            anchor.addChild(ground)
        }

        func update(position: (x: Float, z: Float), heading: Double,
                    cameraMode: DriveCameraMode, roads: [RoadVisual]) {
            if Set(roads.map(\.id)) != roadIDs {
                rebuildRoads(roads)
            }

            let yaw = Float(heading * .pi / 180)
            car.position = [position.x, 0, position.z]
            car.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

            let sinYaw = sin(yaw)
            let cosYaw = cos(yaw)
            let cameraPosition: SIMD3<Float>
            let target: SIMD3<Float>
            if cameraMode == .follow {
                cameraPosition = [position.x - sinYaw * 9.0, 4.8, position.z - cosYaw * 9.0]
                target = [position.x, 0.9, position.z + 1.1]
            } else {
                cameraPosition = [position.x + sinYaw * 0.05, 1.42, position.z + cosYaw * 0.05]
                target = [position.x + sinYaw * 35, 1.35, position.z + cosYaw * 35]
            }
            camera.look(at: target, from: cameraPosition, relativeTo: nil)
        }

        private func rebuildRoads(_ roads: [RoadVisual]) {
            for child in anchor.children where child.name.hasPrefix("road-") {
                child.removeFromParent()
            }
            roadIDs = Set(roads.map(\.id))
            let asphalt = SimpleMaterial(color: UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1), isMetallic: false)
            let line = SimpleMaterial(color: UIColor(red: 0.92, green: 0.79, blue: 0.32, alpha: 1), isMetallic: false)

            for road in roads {
                let segment = Entity()
                segment.name = "road-\(road.id)"
                let surface = ModelEntity(mesh: .generateBox(size: [road.width, 0.09, max(1, road.length)]), materials: [asphalt])
                surface.position = [0, -0.035, 0]
                segment.addChild(surface)

                if road.width >= 5 {
                    let centerLine = ModelEntity(mesh: .generateBox(size: [0.09, 0.015, max(0.5, road.length * 0.82)]), materials: [line])
                    centerLine.position.y = 0.02
                    segment.addChild(centerLine)
                }
                segment.position = [road.x, -0.02, road.z]
                segment.orientation = simd_quatf(angle: road.yaw, axis: [0, 1, 0])
                anchor.addChild(segment)
            }
        }
    }
}
