import Foundation
import CoreLocation
import MapKit
import Combine

@MainActor
final class NavigationSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var theme: MapTheme = .losAngeles
    @Published private(set) var status = "GPS NAVIGATION"
    @Published private(set) var route: MKRoute?
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: String?
    @Published var pendingCenter: CLLocationCoordinate2D?

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        status = "WAITING FOR GPS"
    }
    func stop() { locationManager.stopUpdatingLocation() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            status = "GPS CONNECTED"
        case .denied, .restricted:
            status = "LOCATION PERMISSION NEEDED"
        default:
            status = "WAITING FOR GPS PERMISSION"
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        if pendingCenter == nil { pendingCenter = location.coordinate }
        status = "GPS · ACCURACY ±\(Int(location.horizontalAccuracy))M"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS SIGNAL UNAVAILABLE"
        self.error = error.localizedDescription
    }
    func centerOnUser() {
        guard let coordinate = currentLocation?.coordinate else {
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
            return
        }
        pendingCenter = coordinate
    }
    func search(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        error = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let currentLocation {
            request.region = MKCoordinateRegion(center: currentLocation.coordinate, latitudinalMeters: 50000, longitudinalMeters: 50000)
        }
        Task {
            defer { isSearching = false }
            do {
                let response = try await MKLocalSearch(request: request).start()
                results = response.mapItems
                if results.isEmpty { error = "No matching places found." }
            } catch { self.error = error.localizedDescription }
        }
    }
    func select(_ item: MKMapItem) {
        guard let destination = item.placemark.location else { return }
        guard let source = currentLocation else {
            pendingCenter = destination.coordinate
            error = "Current GPS location is not available yet."
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source.coordinate))
        request.destination = item
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        Task {
            do {
                let response = try await MKDirections(request: request).calculate()
                guard let best = response.routes.first else {
                    self.error = "No driving route was found."
                    return
                }
                route = best
                status = "ROUTE READY · \(Int(best.expectedTravelTime / 60)) MIN"
            } catch { self.error = error.localizedDescription }
        }
    }
    func clearRoute() {
        route = nil
        status = "GPS NAVIGATION"
    }
}
