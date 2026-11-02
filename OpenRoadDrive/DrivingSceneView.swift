import SceneKit
import SwiftUI
import UIKit

struct DrivingSceneView: UIViewRepresentable {
    @ObservedObject var drive: DriveSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.makeScene()
        view.backgroundColor = UIColor(red: 0.43, green: 0.65, blue: 0.82, alpha: 1)
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .none
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.scene?.isPaused = false
        context.coordinator.install(in: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(
            position: drive.worldPosition,
            elevation: drive.elevationMeters,
            heading: drive.heading,
            cameraMode: drive.cameraMode,
            roads: drive.roads,
            terrain: drive.terrain
        )
    }

    final class Coordinator {
        private let scene = SCNScene()
        private let world = SCNNode()
        private let car = SCNNode()
        private let cameraNode = SCNNode()
        private var roadIDs: Set<Int> = []
        private var terrainSignature = ""

        func makeScene() -> SCNScene {
            scene.rootNode.addChildNode(world)
            scene.background.contents = UIColor(red: 0.43, green: 0.65, blue: 0.82, alpha: 1)
            scene.fogColor = UIColor(red: 0.57, green: 0.70, blue: 0.75, alpha: 1)
            scene.fogStartDistance = 240
            scene.fogEndDistance = 1_100
            return scene
        }

        func install(in view: SCNView) {
            let camera = SCNCamera()
            camera.fieldOfView = 70
            camera.zNear = 0.1
            camera.zFar = 1_400
            camera.wantsHDR = false
            camera.bloomIntensity = 0
            cameraNode.camera = camera
            scene.rootNode.addChildNode(cameraNode)

            let sun = SCNNode()
            sun.light = SCNLight()
            sun.light?.type = .directional
            sun.light?.intensity = 1_050
            sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
            scene.rootNode.addChildNode(sun)

            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .ambient
            fill.light?.intensity = 420
            scene.rootNode.addChildNode(fill)

            let fallbackGround = SCNFloor()
            fallbackGround.reflectivity = 0
            fallbackGround.firstMaterial?.diffuse.contents = UIColor(red: 0.19, green: 0.32, blue: 0.20, alpha: 1)
            let groundNode = SCNNode(geometry: fallbackGround)
            groundNode.name = "fallback-ground"
            groundNode.position.y = -0.1
            world.addChildNode(groundNode)

            buildCar()
            world.addChildNode(car)
            view.pointOfView = cameraNode
        }

        private func buildCar() {
            let paint = material(UIColor(red: 0.035, green: 0.28, blue: 0.82, alpha: 1), metallic: 0.78, roughness: 0.24)
            let glass = material(UIColor(red: 0.025, green: 0.065, blue: 0.105, alpha: 1), metallic: 0.42, roughness: 0.18)
            let rubber = material(UIColor(white: 0.025, alpha: 1), metallic: 0, roughness: 0.95)
            let alloy = material(UIColor(white: 0.68, alpha: 1), metallic: 0.85, roughness: 0.28)
            let lamp = material(UIColor(red: 0.92, green: 0.96, blue: 1, alpha: 1), metallic: 0.2, roughness: 0.18)

            addBox(to: car, size: SCNVector3(1.9, 0.58, 4.15), position: SCNVector3(0, 0.68, 0), material: paint)
            addBox(to: car, size: SCNVector3(1.78, 0.18, 1.05), position: SCNVector3(0, 1.00, 1.43), material: paint)
            addBox(to: car, size: SCNVector3(1.48, 0.70, 1.92), position: SCNVector3(0, 1.28, -0.05), material: glass)
            addBox(to: car, size: SCNVector3(1.54, 0.12, 1.98), position: SCNVector3(0, 1.66, -0.05), material: paint)
            addBox(to: car, size: SCNVector3(1.82, 0.16, 0.18), position: SCNVector3(0, 0.53, -2.05), material: paint)

            for x: Float in [-0.96, 0.96] {
                for z: Float in [-1.34, 1.34] {
                    let tire = SCNCylinder(radius: 0.37, height: 0.24)
                    tire.radialSegmentCount = 16
                    tire.firstMaterial = rubber
                    let wheel = SCNNode(geometry: tire)
                    wheel.position = SCNVector3(x, 0.40, z)
                    wheel.eulerAngles.z = Float.pi / 2
                    car.addChildNode(wheel)

                    let hub = SCNCylinder(radius: 0.17, height: 0.255)
                    hub.radialSegmentCount = 12
                    hub.firstMaterial = alloy
                    let hubNode = SCNNode(geometry: hub)
                    hubNode.position = wheel.position
                    hubNode.eulerAngles.z = Float.pi / 2
                    car.addChildNode(hubNode)
                }
            }

            for x: Float in [-0.60, 0.60] {
                addBox(to: car, size: SCNVector3(0.34, 0.13, 0.05), position: SCNVector3(x, 0.82, 2.08), material: lamp)
                addBox(to: car, size: SCNVector3(0.30, 0.10, 0.05), position: SCNVector3(x, 0.78, -2.08), material: material(.red, metallic: 0.1, roughness: 0.3))
            }
        }

        private func addBox(to parent: SCNNode, size: SCNVector3, position: SCNVector3, material: SCNMaterial) {
            let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0.07)
            box.firstMaterial = material
            let node = SCNNode(geometry: box)
            node.position = position
            parent.addChildNode(node)
        }

        private func material(_ color: UIColor, metallic: CGFloat, roughness: CGFloat) -> SCNMaterial {
            let result = SCNMaterial()
            result.diffuse.contents = color
            result.metalness.contents = metallic
            result.roughness.contents = roughness
            result.lightingModel = .physicallyBased
            return result
        }

        func update(position: (x: Float, z: Float), elevation: Float, heading: Double,
                    cameraMode: DriveCameraMode, roads: [RoadVisual], terrain: TerrainVisual?) {
            if Set(roads.map(\.id)) != roadIDs {
                rebuildRoads(roads)
            }
            if let terrain {
                let signature = "\(terrain.columns)-\(terrain.rows)-\(terrain.elevations.first ?? 0)-\(terrain.elevations.last ?? 0)"
                if signature != terrainSignature {
                    rebuildTerrain(terrain)
                    terrainSignature = signature
                }
            }

            let yaw = Float(heading * .pi / 180)
            let carY = elevation + 0.12
            car.position = SCNVector3(position.x, carY, position.z)
            car.eulerAngles.y = yaw

            let cameraPosition: SCNVector3
            let target: SCNVector3
            if cameraMode == .follow {
                cameraPosition = SCNVector3(position.x - sin(yaw) * 10.5, carY + 4.8, position.z - cos(yaw) * 10.5)
                target = SCNVector3(position.x, carY + 0.85, position.z + 1.5)
            } else {
                cameraPosition = SCNVector3(position.x + sin(yaw) * 0.12, carY + 1.48, position.z + cos(yaw) * 0.12)
                target = SCNVector3(position.x + sin(yaw) * 42, carY + 1.40, position.z + cos(yaw) * 42)
            }
            cameraNode.position = cameraPosition
            cameraNode.look(at: target)
        }

        private func rebuildTerrain(_ terrain: TerrainVisual) {
            world.childNodes.filter { $0.name == "terrain-mesh" }.forEach { $0.removeFromParentNode() }
            guard terrain.elevations.count == terrain.columns * terrain.rows else { return }

            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            vertices.reserveCapacity(terrain.elevations.count)
            indices.reserveCapacity((terrain.columns - 1) * (terrain.rows - 1) * 6)

            for row in 0..<terrain.rows {
                for column in 0..<terrain.columns {
                    let index = row * terrain.columns + column
                    let x = terrain.originX + Float(column) * terrain.spacing
                    let z = terrain.originZ + Float(row) * terrain.spacing
                    vertices.append(SCNVector3(x, terrain.elevations[index], z))
                }
            }

            for row in 0..<(terrain.rows - 1) {
                for column in 0..<(terrain.columns - 1) {
                    let a = Int32(row * terrain.columns + column)
                    let b = a + 1
                    let c = a + Int32(terrain.columns)
                    let d = c + 1
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }

            let geometry = makeMesh(vertices: vertices, indices: indices,
                                    color: UIColor(red: 0.19, green: 0.34, blue: 0.20, alpha: 1))
            geometry.firstMaterial?.roughness.contents = 1
            let node = SCNNode(geometry: geometry)
            node.name = "terrain-mesh"
            world.addChildNode(node)
            world.childNodes.first(where: { $0.name == "fallback-ground" })?.isHidden = true
        }

        private func rebuildRoads(_ roads: [RoadVisual]) {
            world.childNodes.filter { $0.name == "road-mesh" || $0.name == "line-mesh" }.forEach { $0.removeFromParentNode() }
            roadIDs = Set(roads.map(\.id))

            var roadVertices: [SCNVector3] = []
            var roadIndices: [Int32] = []
            var lineVertices: [SCNVector3] = []
            var lineIndices: [Int32] = []

            for road in roads {
                let dx = road.endX - road.startX
                let dz = road.endZ - road.startZ
                let length = hypot(dx, dz)
                guard length > 0.5 else { continue }
                let px = -dz / length * road.width * 0.5
                let pz = dx / length * road.width * 0.5
                let base = Int32(roadVertices.count)
                roadVertices.append(contentsOf: [
                    SCNVector3(road.startX - px, road.startY, road.startZ - pz),
                    SCNVector3(road.endX - px, road.endY, road.endZ - pz),
                    SCNVector3(road.endX + px, road.endY, road.endZ + pz),
                    SCNVector3(road.startX + px, road.startY, road.startZ + pz)
                ])
                roadIndices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])

                if road.width >= 5.5 {
                    let dashLength: Float = 2.2
                    let count = max(1, Int(length / 13))
                    for dash in 0..<count {
                        let t = (Float(dash) + 0.5) / Float(count)
                        let cx = road.startX + dx * t
                        let cz = road.startZ + dz * t
                        let cy = road.startY + (road.endY - road.startY) * t + 0.025
                        let ex = dx / length * dashLength * 0.5
                        let ez = dz / length * dashLength * 0.5
                        let lx = -dz / length * 0.045
                        let lz = dx / length * 0.045
                        let lb = Int32(lineVertices.count)
                        lineVertices.append(contentsOf: [
                            SCNVector3(cx - ex - lx, cy, cz - ez - lz),
                            SCNVector3(cx + ex - lx, cy, cz + ez - lz),
                            SCNVector3(cx + ex + lx, cy, cz + ez + lz),
                            SCNVector3(cx - ex + lx, cy, cz - ez + lz)
                        ])
                        lineIndices.append(contentsOf: [lb, lb + 1, lb + 2, lb, lb + 2, lb + 3])
                    }
                }
            }

            if !roadVertices.isEmpty {
                let geometry = makeMesh(vertices: roadVertices, indices: roadIndices,
                                         color: UIColor(red: 0.105, green: 0.115, blue: 0.13, alpha: 1))
                let node = SCNNode(geometry: geometry)
                node.name = "road-mesh"
                world.addChildNode(node)
            }
            if !lineVertices.isEmpty {
                let geometry = makeMesh(vertices: lineVertices, indices: lineIndices,
                                         color: UIColor(red: 0.96, green: 0.76, blue: 0.20, alpha: 1))
                let node = SCNNode(geometry: geometry)
                node.name = "line-mesh"
                world.addChildNode(node)
            }
        }

        private func makeMesh(vertices: [SCNVector3], indices: [Int32], color: UIColor) -> SCNGeometry {
            let source = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let surface = SCNMaterial()
            surface.diffuse.contents = color
            surface.metalness.contents = 0.08
            surface.roughness.contents = 0.95
            surface.isDoubleSided = true
            return SCNGeometry(sources: [source], elements: [element]).withMaterial(surface)
        }
    }
}

private extension SCNGeometry {
    func withMaterial(_ material: SCNMaterial) -> SCNGeometry {
        materials = [material]
        return self
    }
}
