import Foundation
import CoreLocation
import MapKit
import Combine
import AVFoundation

struct SavedDestination: Identifiable, Codable, Equatable {
    var id: String { name + "|" + String(latitude) + "|" + String(longitude) }
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String

    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = name
        return item
    }
}

@MainActor
final class NavigationSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var theme: MapTheme = MapTheme(rawValue: UserDefaults.standard.string(forKey: "MiniMap.theme") ?? "") ?? .losAngeles {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "MiniMap.theme") }
    }
    @Published private(set) var status = "GPS NAVIGATION"
    @Published private(set) var route: MKRoute?
    @Published private(set) var routeOptions: [MKRoute] = []
    @Published private(set) var selectedRouteIndex = 0
    @Published var avoidTolls: Bool = UserDefaults.standard.bool(forKey: "MiniMap.avoidTolls") { didSet { UserDefaults.standard.set(avoidTolls, forKey: "MiniMap.avoidTolls") } }
    @Published var avoidHighways: Bool = UserDefaults.standard.bool(forKey: "MiniMap.avoidHighways") { didSet { UserDefaults.standard.set(avoidHighways, forKey: "MiniMap.avoidHighways") } }
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var savedDestinations: [SavedDestination] = (try? JSONDecoder().decode([SavedDestination].self, from: UserDefaults.standard.data(forKey: "MiniMap.savedDestinations") ?? Data())) ?? []
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
    private var activeSearchID = UUID()
    private var directionsTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
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
        currentSpeed = location.speed >= 0 ? max(0, location.speed) : -1
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
        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        error = nil
        results = []
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let currentLocation {
            request.region = MKCoordinateRegion(center: currentLocation.coordinate, latitudinalMeters: 50000, longitudinalMeters: 50000)
        }
        searchTask = Task {
            defer {
                if activeSearchID == searchID { isSearching = false }
            }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled, activeSearchID == searchID else { return }
                results = response.mapItems
                if results.isEmpty { error = "No matching places found." }
            } catch {
                if !Task.isCancelled, activeSearchID == searchID { self.error = error.localizedDescription }
            }
        }
    }

    func select(_ item: MKMapItem) {
        destination = item
        calculateRoute(to: item)
    }

    func saveCurrentDestination() {
        guard let destination, let name = destination.name else { return }
        let coordinate = destination.placemark.coordinate
        let saved = SavedDestination(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: destination.placemark.title ?? ""
        )
        savedDestinations.removeAll { $0.name == saved.name && $0.latitude == saved.latitude && $0.longitude == saved.longitude }
        savedDestinations.insert(saved, at: 0)
        savedDestinations = Array(savedDestinations.prefix(30))
        if let data = try? JSONEncoder().encode(savedDestinations) {
            UserDefaults.standard.set(data, forKey: "MiniMap.savedDestinations")
        }
    }

    func selectSavedDestination(_ saved: SavedDestination) {
        select(saved.mapItem)
    }

    func removeSavedDestination(_ saved: SavedDestination) {
        savedDestinations.removeAll { $0.id == saved.id }
        if let data = try? JSONEncoder().encode(savedDestinations) {
            UserDefaults.standard.set(data, forKey: "MiniMap.savedDestinations")
        }
    }

    private func calculateRoute(to item: MKMapItem, preservingNavigation: Bool = false) {
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
        request.tollRoads = avoidTolls
        request.highway = avoidHighways
        directionsTask = Task {
            do {
                let response = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled, let best = response.routes.first else {
                    if !Task.isCancelled { error = "No driving route was found." }
                    return
                }
                routeOptions = response.routes.sorted { $0.expectedTravelTime < $1.expectedTravelTime }
                selectedRouteIndex = routeOptions.firstIndex(where: { $0 === best }) ?? 0
                route = routeOptions[selectedRouteIndex]
                currentStepIndex = 0
                totalSteps = best.steps.filter { !$0.instructions.isEmpty }.count
                remainingDistance = best.distance
                remainingTime = best.expectedTravelTime
                nextInstruction = best.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Continue to your destination"
                nextManeuverDistance = best.steps.first(where: { !$0.instructions.isEmpty }).map { distanceToManeuver(from: source.coordinate, step: $0) } ?? best.distance
                lastSpokenStep = -1
                if preservingNavigation {
                    isNavigating = true
                    status = "NAVIGATION ACTIVE · ROUTE UPDATED"
                    lastSpokenStep = -1
                    speak(nextInstruction)
                    lastSpokenStep = currentStepIndex
                } else {
                    isNavigating = false
                    status = "ROUTE READY · \(Int(best.expectedTravelTime / 60)) MIN"
                }
                pendingCenter = source.coordinate
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    func selectRoute(_ index: Int) {
        guard routeOptions.indices.contains(index), !isNavigating else { return }
        selectedRouteIndex = index
        route = routeOptions[index]
        currentStepIndex = 0
        totalSteps = route?.steps.filter { !$0.instructions.isEmpty }.count ?? 0
        remainingDistance = route?.distance ?? 0
        remainingTime = route?.expectedTravelTime ?? 0
        if let route, let source = currentLocation {
            nextInstruction = route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Continue to your destination"
            nextManeuverDistance = route.steps.first(where: { !$0.instructions.isEmpty }).map { distanceToManeuver(from: source.coordinate, step: $0) } ?? route.distance
            pendingCenter = source.coordinate
        }
        status = "ROUTE READY · \(Int(remainingTime / 60)) MIN"
    }

    func updateRoutePreferences(avoidTolls: Bool, avoidHighways: Bool) {
        let changed = self.avoidTolls != avoidTolls || self.avoidHighways != avoidHighways
        self.avoidTolls = avoidTolls
        self.avoidHighways = avoidHighways
        if changed, let destination, !isNavigating { calculateRoute(to: destination) }
    }

    func beginNavigation() {
        guard route != nil else { return }
        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
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
        routeOptions = []
        selectedRouteIndex = 0
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
            calculateRoute(to: destination, preservingNavigation: true)
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
        nextManeuverDistance = distanceToManeuver(from: location.coordinate, step: step)
        let remainingSteps = steps.dropFirst(nextIndex)
        let distanceToCurrentManeuver = distance(from: location.coordinate, to: step)
        let laterStepDistance = remainingSteps.dropFirst().reduce(0) { $0 + $1.distance }
        remainingDistance = distanceToCurrentManeuver + laterStepDistance
        remainingTime = route.distance > 0
            ? min(route.expectedTravelTime, remainingDistance * route.expectedTravelTime / route.distance)
            : 0
        if location.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)) < 35 {
            speak("You have arrived at your destination.")
            clearRoute()
            status = "ARRIVED"
        }
    }

    private func distanceToManeuver(from coordinate: CLLocationCoordinate2D, step: MKRoute.Step) -> CLLocationDistance {
        guard step.polyline.pointCount > 0 else { return .greatestFiniteMagnitude }
        let start = step.polyline.points()[0].coordinate
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))
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
        let language = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
        speech.speak(utterance)
    }
}
