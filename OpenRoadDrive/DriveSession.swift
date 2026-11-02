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
    @Published private(set) var terrain: TerrainVisual?
    @Published private(set) var elevationMeters: Float = 0
    @Published private(set) var worldRevision = 0
    @Published private(set) var roadStatus = "LOADING WORLD"
    @Published private(set) var isAccelerating = false
    @Published private(set) var isBraking = false
    @Published private(set) var gpsEnabled = false
    @Published private(set) var roadReady = false
    @Published private(set) var isLoadingWorld = false
    @Published private(set) var isOnRoad = false
    @Published private(set) var controllerConnected = false
    @Published var cameraMode: DriveCameraMode = .follow

    private let locationManager = CLLocationManager()
    private var simulationTask: Task<Void, Never>?
    private var controllerObservers: [NSObjectProtocol] = []
    private var roadEdges: [RoadEdge] = []
    private var origin = CLLocationCoordinate2D(latitude: 41.001, longitude: -75.181)
    private var localX: Float = 0
    private var localZ: Float = 0
    private var velocityMS = 0.0
    private var steeringInput = 0.0
    private var tapSteeringTime = 0.0
    private var roadCheckTime = 0.0
    private var nearestRoadLimitKPH = 25.0
    private var throttle = false
    private var brake = false
    private var isLoadingRoads = false

    var worldPosition: (x: Float, z: Float) { (localX, localZ) }

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
                try? await Task.sleep(nanoseconds: 33_333_333)
                guard !Task.isCancelled else { break }
                self?.tick(deltaTime: 1.0 / 30.0)
            }
        }
    }

    func stop() {
        simulationTask?.cancel()
        simulationTask = nil
    }

    func toggleAcceleration() { setThrottle(!throttle) }
    func toggleBrake() { setBrake(!brake) }

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

    // Continuous input is used by analog gamepad sticks.
    func steer(_ direction: Double) {
        steeringInput = max(-1, min(1, direction))
        tapSteeringTime = 0
    }

    // Touch steering gives a short, predictable steering pulse per tap.
    func tapSteer(_ direction: Double) {
        steeringInput = max(-1, min(1, direction))
        tapSteeringTime = 0.28
    }

    func changeCamera() { cameraMode = cameraMode.next }

    func retryWorldLoad() {
        Task { await loadRoads(near: coordinate) }
    }

    func searchLocation(_ query: String) {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return }
        roadStatus = "SEARCHING FOR LOCATION"
        Task {
            do {
                let matches = try await CLGeocoder().geocodeAddressString(search)
                guard let coordinate = matches.first?.location?.coordinate else {
                    roadStatus = "LOCATION NOT FOUND"
                    return
                }
                await loadRoads(near: coordinate)
            } catch {
                roadStatus = "LOCATION SEARCH FAILED"
            }
        }
    }

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
        if let controller = GCController.controllers().first {
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
                self?.steer(abs(value) > 0.12 ? Double(value) : 0)
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
        isLoadingWorld = true
        defer {
            isLoadingRoads = false
            isLoadingWorld = false
        }
        roadStatus = "LOADING NEARBY ROADS & TERRAIN"
        roadReady = false

        do {
            let fetched = try await RoadNetwork.fetch(near: position)
            roadEdges = fetched.edges
            origin = position
            coordinate = position
            localX = 0
            localZ = 0
            roads = fetched.roads
            terrain = fetched.terrain
            elevationMeters = RoadNetwork.height(at: position, origin: origin, terrain: fetched.terrain)
            worldRevision &+= 1
            updateNearestRoad()
            roadReady = true
            roadStatus = fetched.edges.isEmpty
                ? "ROAD DATA UNAVAILABLE · FREE DRIVE"
                : "WORLD READY · FREE DRIVE"
        } catch {
            roadStatus = "WORLD DATA UNAVAILABLE · CHECK CONNECTION"
            roadReady = false
            velocityMS = 0
            speedKPH = 0
            setThrottle(false)
        }
    }

    private func tick(deltaTime dt: Double) {
        guard roadReady, let terrain else { return }

        if Self.distance(coordinate, origin) > 520, !isLoadingRoads {
            let streamingCenter = coordinate
            Task { await loadRoads(near: streamingCenter) }
            return
        }

        if tapSteeringTime > 0 {
            tapSteeringTime -= dt
            if tapSteeringTime <= 0 { steeringInput = 0 }
        }

        roadCheckTime -= dt
        if roadCheckTime <= 0 {
            updateNearestRoad()
            roadCheckTime = 0.22
        }

        let speedLimit = isOnRoad ? nearestRoadLimitKPH : 28.0
        if throttle {
            if velocityMS < 0 {
                velocityMS = min(0, velocityMS + 8.5 * dt)
            } else {
                velocityMS += 3.6 * dt
            }
        } else if brake {
            if velocityMS > 0 {
                velocityMS = max(0, velocityMS - 9.0 * dt)
            } else {
                velocityMS = max(-8.0, velocityMS - 2.6 * dt)
            }
        } else {
            if velocityMS > 0 { velocityMS = max(0, velocityMS - 0.42 * dt) }
            else if velocityMS < 0 { velocityMS = min(0, velocityMS + 0.42 * dt) }
        }

        velocityMS = min(velocityMS, min(speedLimit / 3.6, 42.0))
        speedKPH = abs(velocityMS) * 3.6

        let yawRate = min(78.0, abs(velocityMS) * 4.8)
        let reverseSign = velocityMS < 0 ? -1.0 : 1.0
        heading = (heading + steeringInput * yawRate * dt * reverseSign + 360)
            .truncatingRemainder(dividingBy: 360)

        let travel = velocityMS * dt
        let radians = heading * .pi / 180
        localX += Float(sin(radians) * travel)
        localZ += Float(cos(radians) * travel)
        distanceMeters += abs(travel)
        coordinate = coordinateForLocalPosition(x: localX, z: localZ)
        elevationMeters = RoadNetwork.height(at: coordinate, origin: origin, terrain: terrain)
    }

    private func updateNearestRoad() {
        guard !roadEdges.isEmpty else {
            isOnRoad = false
            nearestRoadLimitKPH = 25
            return
        }

        var bestDistance = Double.greatestFiniteMagnitude
        var bestWidth: Double = 0
        var bestLimit = 25.0

        for edge in roadEdges {
            let a = RoadNetwork.localPosition(edge.start, origin: origin)
            let b = RoadNetwork.localPosition(edge.end, origin: origin)
            let dx = Double(b.x - a.x)
            let dz = Double(b.z - a.z)
            let denominator = dx * dx + dz * dz
            guard denominator > 0 else { continue }
            let px = Double(localX - a.x)
            let pz = Double(localZ - a.z)
            let t = max(0, min(1, (px * dx + pz * dz) / denominator))
            let nearestX = Double(a.x) + dx * t
            let nearestZ = Double(a.z) + dz * t
            let distance = hypot(Double(localX) - nearestX, Double(localZ) - nearestZ)
            if distance < bestDistance {
                bestDistance = distance
                bestWidth = Double(edge.width)
                bestLimit = edge.speedLimit
            }
        }

        isOnRoad = bestDistance <= bestWidth * 0.5 + 2.2
        nearestRoadLimitKPH = isOnRoad ? bestLimit : 28.0
    }

    private func coordinateForLocalPosition(x: Float, z: Float) -> CLLocationCoordinate2D {
        let radius = 6_371_008.8
        let latitude = origin.latitude + Double(z) / radius * 180 / .pi
        let latitudeScale = max(0.15, cos(origin.latitude * .pi / 180))
        let longitude = origin.longitude + Double(x) / (radius * latitudeScale) * 180 / .pi
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
