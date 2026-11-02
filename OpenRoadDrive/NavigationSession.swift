import Foundation
import CoreLocation
import MapKit
import Combine
import AVFoundation

@MainActor
final class NavigationSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var theme: MapTheme = .losAngeles
    @Published private(set) var status = "GPS NAVIGATION"
    @Published private(set) var route: MKRoute?
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: String?
    @Published var pendingCenter: CLLocationCoordinate2D?
    @Published private(set) var isNavigating = false
    @Published private(set) var currentSpeed = 0.0
    @Published private(set) var nextInstruction = "Choose a destination"
    @Published private(set) var nextManeuverDistance = 0.0
    @Published private(set) var remainingDistance = 0.0
    @Published private(set) var remainingTime = 0.0
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var totalSteps = 0

    private let locationManager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private var currentLocation: CLLocation?
    private var destination: MKMapItem?
    private var lastSpokenStep = -1
    private var lastRerouteTime = Date.distantPast
    private var searchTask: Task<Void, Never>?
    private var directionsTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        status = "WAITING FOR GPS"
    }
    func stop() {
        if !isNavigating { locationManager.stopUpdatingLocation() }
    }

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
        guard let location = locations.last, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100 else { return }
        currentLocation = location
        currentSpeed = max(0, location.speed)
        if pendingCenter == nil { pendingCenter = location.coordinate }
        if !isNavigating { status = "GPS · ACCURACY ±\(Int(location.horizontalAccuracy))M" }
        updateNavigation(at: location)
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
        searchTask?.cancel()
        isSearching = true
        error = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let currentLocation {
            request.region = MKCoordinateRegion(center: currentLocation.coordinate, latitudinalMeters: 50000, longitudinalMeters: 50000)
        }
        searchTask = Task {
            defer { isSearching = false }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = response.mapItems
                if results.isEmpty { error = "No matching places found." }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    func select(_ item: MKMapItem) {
        destination = item
        calculateRoute(to: item)
    }

    private func calculateRoute(to item: MKMapItem) {
        guard let source = currentLocation else {
            error = "Waiting for a reliable GPS position."
            return
        }
        directionsTask?.cancel()
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source.coordinate))
        request.destination = item
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        directionsTask = Task {
            do {
                let response = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled, let best = response.routes.first else {
                    if !Task.isCancelled { error = "No driving route was found." }
                    return
                }
                route = best
                currentStepIndex = 0
                totalSteps = best.steps.filter { !$0.instructions.isEmpty }.count
                remainingDistance = best.distance
                remainingTime = best.expectedTravelTime
                nextInstruction = best.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Continue to your destination"
                nextManeuverDistance = best.steps.first(where: { !$0.instructions.isEmpty }).map { distance(from: source.coordinate, to: $0) } ?? best.distance
                lastSpokenStep = -1
                isNavigating = false
                status = "ROUTE READY · \(Int(best.expectedTravelTime / 60)) MIN"
                pendingCenter = source.coordinate
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    func beginNavigation() {
        guard route != nil else { return }
        isNavigating = true
        locationManager.startUpdatingLocation()
        status = "NAVIGATION ACTIVE"
        lastSpokenStep = -1
        speak(nextInstruction)
        lastSpokenStep = currentStepIndex
    }

    func pauseNavigation() {
        isNavigating = false
        speech.stopSpeaking(at: .immediate)
        status = route == nil ? "GPS NAVIGATION" : "ROUTE PAUSED"
    }

    func clearRoute() {
        pauseNavigation()
        route = nil
        destination = nil
        totalSteps = 0
        currentStepIndex = 0
        remainingDistance = 0
        remainingTime = 0
        nextInstruction = "Choose a destination"
        status = "GPS NAVIGATION"
    }

    private func updateNavigation(at location: CLLocation) {
        guard isNavigating, let route, let destination else { return }
        let steps = route.steps.filter { !$0.instructions.isEmpty }
        guard !steps.isEmpty else { return }
        if distanceFromRoute(location.coordinate, route.polyline) > 110,
           Date().timeIntervalSince(lastRerouteTime) > 15 {
            lastRerouteTime = Date()
            status = "REROUTING…"
            calculateRoute(to: destination)
            return
        }

        var nextIndex = min(currentStepIndex, steps.count - 1)
        while nextIndex < steps.count - 1 {
            let distance = distance(from: location.coordinate, to: steps[nextIndex])
            if distance < 55 { nextIndex += 1 } else { break }
        }
        if nextIndex != currentStepIndex {
            currentStepIndex = nextIndex
            if lastSpokenStep != nextIndex {
                speak(steps[nextIndex].instructions)
                lastSpokenStep = nextIndex
            }
        }
        let step = steps[nextIndex]
        nextInstruction = step.instructions
        nextManeuverDistance = distance(from: location.coordinate, to: step)
        let remainingSteps = steps.dropFirst(nextIndex)
        remainingDistance = remainingSteps.reduce(0) { $0 + $1.distance }
        remainingTime = route.distance > 0 ? remainingDistance * route.expectedTravelTime / route.distance : 0
        if location.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)) < 35 {
            speak("You have arrived at your destination.")
            clearRoute()
            status = "ARRIVED"
        }
    }

    private func distance(from coordinate: CLLocationCoordinate2D, to step: MKRoute.Step) -> CLLocationDistance {
        guard step.polyline.pointCount > 0 else { return .greatestFiniteMagnitude }
        let end = step.polyline.points()[step.polyline.pointCount - 1].coordinate
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    private func distanceFromRoute(_ coordinate: CLLocationCoordinate2D, _ line: MKPolyline) -> CLLocationDistance {
        guard line.pointCount > 1 else { return .greatestFiniteMagnitude }
        let point = MKMapPoint(coordinate)
        let points = line.points()
        var minimum = Double.greatestFiniteMagnitude
        for index in 0..<(line.pointCount - 1) {
            let a = points[index]
            let b = points[index + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((point.x-a.x)*dx + (point.y-a.y)*dy) / length))
            let projected = MKMapPoint(x: a.x + t*dx, y: a.y + t*dy)
            minimum = min(minimum, point.distance(to: projected))
        }
        return minimum * MKMetersPerMapPointAtLatitude(coordinate.latitude)
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        speech.speak(utterance)
    }
}
