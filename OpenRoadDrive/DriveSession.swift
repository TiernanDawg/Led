import Combine
import CoreLocation
import Foundation

enum DriveCameraMode: String, CaseIterable {
    case follow = "FOLLOW"
    case cockpit = "COCKPIT"

    var next: DriveCameraMode {
        self == .follow ? .cockpit : .follow
    }
}

@MainActor
final class DriveSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate = CLLocationCoordinate2D(latitude: 41.001, longitude: -75.181)
    @Published private(set) var heading = 0.0
    @Published private(set) var speedKPH = 0.0
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var isAccelerating = false
    @Published private(set) var isBraking = false
    @Published private(set) var gpsEnabled = false

    @Published var cameraMode: DriveCameraMode = .follow

    private let earthRadius = 6_371_008.8
    private let locationManager = CLLocationManager()
    private var simulationTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 2
    }

    func start() {
        guard simulationTask == nil else { return }
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { break }
                self?.tick(deltaTime: 0.1)
            }
        }
    }

    func stop() {
        simulationTask?.cancel()
        simulationTask = nil
    }

    func toggleAcceleration() {
        isAccelerating.toggle()
        if isAccelerating { isBraking = false }
    }

    func toggleBrake() {
        isBraking.toggle()
        if isBraking { isAccelerating = false }
    }

    func steer(_ direction: Double) {
        let steeringRate = 5.0 + min(speedKPH / 18.0, 5.0)
        heading = normalizedHeading(heading + direction * steeringRate)
    }

    func changeCamera() {
        cameraMode = cameraMode.next
    }

    func enableGPS() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            gpsEnabled = false
        @unknown default:
            gpsEnabled = false
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
        coordinate = latest.coordinate
        gpsEnabled = true
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        gpsEnabled = false
        manager.stopUpdatingLocation()
    }

    private func tick(deltaTime dt: Double) {
        if isBraking {
            speedKPH = max(0, speedKPH - 28 * dt)
        } else if isAccelerating {
            speedKPH = min(180, speedKPH + 13 * dt)
        } else {
            speedKPH = max(0, speedKPH - 3.2 * dt)
        }

        let meters = (speedKPH / 3.6) * dt
        guard meters > 0 else { return }

        let bearing = heading * .pi / 180
        let latitudeRadians = coordinate.latitude * .pi / 180
        let angularDistance = meters / earthRadius

        let nextLatitude = coordinate.latitude + (angularDistance * cos(bearing)) * 180 / .pi
        let longitudeScale = max(0.01, cos(latitudeRadians))
        let nextLongitude = coordinate.longitude +
            (angularDistance * sin(bearing) / longitudeScale) * 180 / .pi

        coordinate = CLLocationCoordinate2D(
            latitude: min(85.0, max(-85.0, nextLatitude)),
            longitude: normalizedLongitude(nextLongitude)
        )
        distanceMeters += meters
    }

    private func normalizedHeading(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private func normalizedLongitude(_ value: Double) -> Double {
        let wrapped = (value + 180).truncatingRemainder(dividingBy: 360)
        return (wrapped < 0 ? wrapped + 360 : wrapped) - 180
    }
}
