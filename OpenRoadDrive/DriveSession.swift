import Combine
import CoreLocation
import Foundation
import GameController

enum DriveCameraMode: String, CaseIterable {
    case follow = "THIRD PERSON"
    case cockpit = "COCKPIT"

    var next: DriveCameraMode { self == .follow ? .cockpit : .follow }
}

@MainActor
final class DriveSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate = CLLocationCoordinate2D(latitude: 41.001, longitude: -75.181)
    @Published private(set) var heading = 0.0
    @Published private(set) var speedKPH = 0.0
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var roads: [RoadVisual] = []
    @Published private(set) var worldRevision = 0
    @Published private(set) var terrain: TerrainVisual?
    @Published private(set) var elevationMeters: Float = 0
    @Published private(set) var roadStatus = "LOADING LOCAL ROADS"
    @Published private(set) var isAccelerating = false
    @Published private(set) var isBraking = false
    @Published private(set) var gpsEnabled = false
    @Published private(set) var roadReady = false
    @Published private(set) var controllerConnected = false
    @Published var cameraMode: DriveCameraMode = .follow

    private let locationManager = CLLocationManager()
    private var simulationTask: Task<Void, Never>?
    private var controllerObservers: [NSObjectProtocol] = []
    private var roadEdges: [RoadEdge] = []
    private var origin = CLLocationCoordinate2D(latitude: 41.001, longitude: -75.181)
    private var activeEdge = -1
    private var forward = true
    private var progress = 0.0
    private var turnRequest = 0.0
    private var throttle = false
    private var brake = false
    private var isLoadingRoads = false

    var worldPosition: (x: Float, z: Float) {
        RoadNetwork.localPosition(coordinate, origin: origin)
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10
        installControllerObservers()
    }

    func start() {
        guard simulationTask == nil else { return }
        Task { await loadRoads(near: coordinate) }
        GCController.startWirelessControllerDiscovery {}
        connectAvailableControllers()
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { break }
                self?.tick(deltaTime: 0.05)
            }
        }
    }

    func stop() {
        simulationTask?.cancel()
        simulationTask = nil
    }

    func toggleAcceleration() {
        setThrottle(!throttle)
    }

    func toggleBrake() {
        setBrake(!brake)
    }

    func setThrottle(_ active: Bool) {
        throttle = active
        isAccelerating = active
        if active {
            brake = false
            isBraking = false
        }
    }

    func setBrake(_ active: Bool) {
        brake = active
        isBraking = active
        if active {
            throttle = false
            isAccelerating = false
        }
    }

    func steer(_ direction: Double) {
        turnRequest = max(-1, min(1, direction))
    }

    func changeCamera() { cameraMode = cameraMode.next }

    func enableGPS() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            roadStatus = "LOCATION PERMISSION DENIED"
        @unknown default:
            roadStatus = "LOCATION UNAVAILABLE"
        }
    }

    private func installControllerObservers() {
        let center = NotificationCenter.default
        controllerObservers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.configure(controller) }
        })
        controllerObservers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.controllerConnected = !GCController.controllers().isEmpty
                self?.setThrottle(false)
                self?.setBrake(false)
                self?.steer(0)
            }
        })
    }

    private func connectAvailableControllers() {
        let available = GCController.controllers()
        if let controller = available.first {
            configure(controller)
        }
    }

    private func configure(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else {
            controllerConnected = false
            return
        }
        controllerConnected = true
        controller.playerIndex = .index1

        pad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
            Task { @MainActor in self?.setThrottle(value > 0.08) }
        }
        pad.leftTrigger.valueChangedHandler = { [weak self] _, value, _ in
            Task { @MainActor in self?.setBrake(value > 0.08) }
        }
        pad.leftThumbstick.xAxis.valueChangedHandler = { [weak self] _, value in
            Task { @MainActor in
                self?.steer(abs(value) > 0.22 ? Double(value) : 0)
            }
        }
        pad.buttonY.valueChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.changeCamera() }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        gpsEnabled = true
        Task { await loadRoads(near: latest.coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        roadStatus = "GPS FIX UNAVAILABLE"
    }

    private func loadRoads(near position: CLLocationCoordinate2D) async {
        guard !isLoadingRoads else { return }
        isLoadingRoads = true
        defer { isLoadingRoads = false }
        roadStatus = "STREAMING WORLD DATA"
        roadReady = false
        do {
            let fetched = try await RoadNetwork.fetch(near: position)
            roadEdges = fetched.edges
            origin = position
            roads = fetched.roads
            terrain = fetched.terrain
            worldRevision &+= 1
            coordinate = position
            guard snapToNearestRoad() else {
                roadStatus = "NO DRIVABLE ROAD NEARBY"
                return
            }
            roadReady = true
            roadStatus = "ROAD NETWORK READY"
        } catch {
            roadStatus = "ROAD DATA UNAVAILABLE · CHECK CONNECTION"
            roadReady = false
            speedKPH = 0
            setThrottle(false)
        }
    }

    private func snapToNearestRoad() -> Bool {
        var bestIndex = -1
        var bestProgress = 0.0
        var bestDistance = Double.greatestFiniteMagnitude
        var bestForward = true

        for (index, edge) in roadEdges.enumerated() {
            let a = RoadNetwork.localPosition(edge.start, origin: origin)
            let b = RoadNetwork.localPosition(edge.end, origin: origin)
            let p = RoadNetwork.localPosition(coordinate, origin: origin)
            let ax = Double(a.x), az = Double(a.z)
            let dx = Double(b.x - a.x), dz = Double(b.z - a.z)
            let denominator = dx * dx + dz * dz
            guard denominator > 0 else { continue }
            let t = max(0, min(1, ((Double(p.x) - ax) * dx + (Double(p.z) - az) * dz) / denominator))
            let px = ax + t * dx
            let pz = az + t * dz
            let distance = hypot(Double(p.x) - px, Double(p.z) - pz)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
                bestProgress = t * edge.length
                let bearing = Self.bearing(from: edge.start, to: edge.end)
                bestForward = Self.angleDifference(heading, bearing) <= Self.angleDifference(heading, bearing + 180)
            }
        }

        guard bestIndex >= 0, bestDistance < 80 else { return false }
        activeEdge = bestIndex
        forward = bestForward
        progress = bestForward ? bestProgress : roadEdges[bestIndex].length - bestProgress
        updateCoordinateOnEdge()
        return true
    }

    private func tick(deltaTime dt: Double) {
        guard roadReady, activeEdge >= 0 else { return }
        if Self.distance(coordinate, origin) > 520, !isLoadingRoads {
            let streamingCenter = coordinate
            Task { await loadRoads(near: streamingCenter) }
            return
        }
        let edge = roadEdges[activeEdge]
        let speed = speedKPH / 3.6
        let acceleration: Double
        if brake { acceleration = -8.5 }
        else if throttle { acceleration = 3.2 }
        else { acceleration = -0.32 }

        let nextSpeed = min(max(0, speed + acceleration * dt), min(edge.speedLimit / 3.6, 42.0))
        speedKPH = nextSpeed * 3.6
        let travel = nextSpeed * dt
        progress += travel
        distanceMeters += travel

        var guardCount = 0
        while progress >= roadEdges[activeEdge].length && guardCount < 4 {
            let overflow = progress - roadEdges[activeEdge].length
            guard let next = chooseNextEdge() else {
                progress = roadEdges[activeEdge].length
                speedKPH = 0
                setThrottle(false)
                roadStatus = "END OF MAPPED ROAD · TURN AROUND"
                break
            }
            activeEdge = next.index
            forward = next.forward
            progress = overflow
            guardCount += 1
        }
        updateCoordinateOnEdge()
    }

    private func chooseNextEdge() -> (index: Int, forward: Bool)? {
        let current = roadEdges[activeEdge]
        let endpoint = forward ? current.end : current.start
        let incoming = Self.bearing(from: current.start, to: current.end) + (forward ? 0 : 180)
        let desired = incoming + turnRequest * 65
        var choices: [(Int, Bool, Double)] = []

        for (index, edge) in roadEdges.enumerated() where index != activeEdge {
            if Self.distance(endpoint, edge.start) < 3 {
                choices.append((index, true, Self.angleDifference(desired, Self.bearing(from: edge.start, to: edge.end))))
            }
            if Self.distance(endpoint, edge.end) < 3 {
                choices.append((index, false, Self.angleDifference(desired, Self.bearing(from: edge.end, to: edge.start))))
            }
        }
        guard let choice = choices.min(by: { $0.2 < $1.2 }) else { return nil }
        turnRequest = 0
        return (choice.0, choice.1)
    }

    private func updateCoordinateOnEdge() {
        guard activeEdge >= 0 else { return }
        let edge = roadEdges[activeEdge]
        let t = max(0, min(1, progress / edge.length))
        let start = forward ? edge.start : edge.end
        let end = forward ? edge.end : edge.start
        coordinate = CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * t,
            longitude: start.longitude + (end.longitude - start.longitude) * t
        )
        heading = Self.bearing(from: start, to: end)
        let startElevation = forward ? edge.startElevation : edge.endElevation
        let endElevation = forward ? edge.endElevation : edge.startElevation
        elevationMeters = startElevation + Float(t) * (endElevation - startElevation)
    }

    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let difference = abs((a - b).truncatingRemainder(dividingBy: 360))
        return min(difference, 360 - difference)
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
