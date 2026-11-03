import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var nav = NavigationSession()
    @State private var showingSearch = false
    @State private var query = ""

    var body: some View {
        ZStack {
            MiniMapView(session: nav).ignoresSafeArea()
            VStack(spacing: 10) {
                header
                if nav.isNavigating { activeGuidance }
                Spacer(minLength: 0)
                if let route = nav.route, !nav.isNavigating { routePreview(route) }
                themePicker
                bottomPanel
            }
            .padding(.horizontal, 13)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(Color.black)
        .sheet(isPresented: $showingSearch) { searchSheet }
        .onAppear { nav.start() }
        .onDisappear { nav.stop() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MiniMap").font(.system(size: 23, weight: .black, design: .rounded))
                Text(nav.status).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if nav.currentSpeed >= 0 {
                VStack(spacing: 0) {
                    Text("\(Int(nav.currentSpeed * 2.23694))")
                        .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                    Text("MPH").font(.system(size: 8, weight: .black))
                }
                .frame(width: 49, height: 48)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            Button { showingSearch = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .bold))
                    .frame(width: 46, height: 46).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            Button { nav.centerOnUser() } label: {
                Image(systemName: "location.north.fill").font(.system(size: 16, weight: .bold))
                    .frame(width: 46, height: 46).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .foregroundStyle(.white)
        .padding(11)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 19))
    }

    private var activeGuidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "arrow.turn.up.right").font(.system(size: 30, weight: .black))
                    .frame(width: 48, height: 48).background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(nav.nextManeuverDistance < 1000
                         ? "\(Int(nav.nextManeuverDistance)) ft"
                         : String(format: "%.1f mi", nav.nextManeuverDistance / 1609.344))
                        .font(.system(size: 23, weight: .black, design: .rounded).monospacedDigit())
                    Text(nav.nextInstruction.uppercased()).font(.system(size: 11, weight: .bold)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(nav.theme.accent).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(String(format: "%.1f", nav.remainingDistance / 1609.344)) MI LEFT")
                Spacer()
                Text("\(max(1, Int(nav.remainingTime / 60))) MIN")
                Spacer()
                Text("STEP \(min(nav.currentStepIndex + 1, max(1, nav.totalSteps)))/\(max(1, nav.totalSteps))")
            }
            .font(.system(size: 8, weight: .black)).foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
    }

    private var progress: CGFloat {
        guard let route = nav.route, route.distance > 0 else { return 0 }
        return CGFloat(max(0, min(1, 1 - nav.remainingDistance / route.distance)))
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MAP WORLDS").font(.system(size: 9, weight: .black)).tracking(1.4)
                Spacer()
                Text(nav.theme.subtitle).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MapTheme.allCases) { theme in
                        Button { nav.theme = theme } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: theme.symbol).font(.system(size: 17, weight: .bold))
                                Text(theme.title).font(.system(size: 9, weight: .black))
                            }
                            .foregroundStyle(nav.theme == theme ? .black : .white)
                            .frame(width: 82, height: 58)
                            .background(nav.theme == theme ? theme.accent : Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .disabled(nav.isNavigating)
            .opacity(nav.isNavigating ? 0.65 : 1)
        }
        .foregroundStyle(.white)
        .padding(11)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 17))
    }

    private var bottomPanel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nav.isNavigating ? "DESTINATION ETA" : nav.route == nil ? "READY TO EXPLORE" : "ROUTE PREVIEW")
                    .font(.system(size: 8, weight: .black)).tracking(1).foregroundStyle(.white.opacity(0.65))
                Text(nav.route.map { "\(String(format: "%.1f mi", nav.isNavigating ? nav.remainingDistance / 1609.344 : $0.distance / 1609.344)) · \(max(1, Int((nav.isNavigating ? nav.remainingTime : $0.expectedTravelTime) / 60))) min" } ?? "Search anywhere to get directions")
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if nav.isNavigating {
                Button { nav.pauseNavigation() } label: { actionLabel("PAUSE", color: .orange) }
            } else if nav.route != nil {
                Button { nav.beginNavigation() } label: { actionLabel("START", color: nav.theme.accent) }
                Button { nav.clearRoute() } label: { actionLabel("END", color: .red) }
            } else {
                Button { showingSearch = true } label: { actionLabel("SEARCH", color: nav.theme.accent) }
            }
        }
        .foregroundStyle(.white)
        .padding(13)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 17))
    }

    private func actionLabel(_ title: String, color: Color) -> some View {
        Text(title).font(.system(size: 10, weight: .black))
            .foregroundStyle(.black).padding(.horizontal, 14).padding(.vertical, 11)
            .background(color, in: Capsule())
    }

    private func routePreview(_ route: MKRoute) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Route ready").font(.system(size: 12, weight: .black))
                Text("\(route.name.isEmpty ? "Recommended driving route" : route.name) · \(route.steps.count) steps")
                    .font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.1f MI", route.distance / 1609.344))
                .font(.system(size: 11, weight: .black).monospacedDigit())
        }
        .foregroundStyle(.white).padding(13)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 16))
    }

    private var searchSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search places or addresses", text: $query)
                        .submitLabel(.search).onSubmit { nav.search(query) }
                }
                .padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                Button { nav.search(query) } label: {
                    Text("Search").fontWeight(.bold).frame(maxWidth: .infinity).padding(12)
                }
                .buttonStyle(.borderedProminent)
                if nav.isSearching { ProgressView("Searching…") }
                if let error = nav.error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                List(nav.results, id: \.self) { item in
                    Button {
                        nav.select(item)
                        showingSearch = false
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name ?? "Place").foregroundStyle(.primary)
                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("Find a destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingSearch = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

enum MapTheme: String, CaseIterable, Identifiable {
    case losAngeles, gotham, voxel, valley
    var id: String { rawValue }
    var title: String {
        switch self {
        case .losAngeles: "SUNSET CITY"
        case .gotham: "GOTHAM"
        case .voxel: "VOXEL"
        case .valley: "PIXEL VALLEY"
        }
    }
    var subtitle: String {
        switch self {
        case .losAngeles: "Cinematic urban"
        case .gotham: "Dark city night"
        case .voxel: "Block-world look"
        case .valley: "Cozy countryside"
        }
    }
    var symbol: String {
        switch self {
        case .losAngeles: "sun.max.fill"
        case .gotham: "moon.stars.fill"
        case .voxel: "cube.fill"
        case .valley: "leaf.fill"
        }
    }
    var accent: Color {
        switch self {
        case .losAngeles: Color(red: 1, green: 0.65, blue: 0.28)
        case .gotham: Color(red: 0.38, green: 0.68, blue: 0.78)
        case .voxel: Color(red: 0.46, green: 0.82, blue: 0.40)
        case .valley: Color(red: 0.94, green: 0.72, blue: 0.43)
        }
    }
    var mapType: MKMapType {
        switch self {
        case .losAngeles: .hybrid
        case .gotham: .mutedStandard
        case .voxel: .satellite
        case .valley: .standard
        }
    }
}

struct MiniMapView: UIViewRepresentable {
    @ObservedObject var session: NavigationSession
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = .follow
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.camera.pitch = 58
        map.camera.altitude = 1100
        map.showsCompass = true
        map.showsScale = true
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        map.mapType = session.theme.mapType
        if let route = session.route, context.coordinator.routeID != ObjectIdentifier(route) {
            map.removeOverlays(map.overlays)
            map.addOverlay(route.polyline)
            context.coordinator.routeID = ObjectIdentifier(route)
            map.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 165, left: 45, bottom: 250, right: 45), animated: true)
        } else if session.route == nil && context.coordinator.routeID != nil {
            map.removeOverlays(map.overlays)
            context.coordinator.routeID = nil
        }
        if context.coordinator.lastTheme != session.theme {
            context.coordinator.lastTheme = session.theme
            map.camera.pitch = session.theme == .voxel ? 68 : 58
        }
        if let center = session.pendingCenter {
            map.setCenter(center, animated: true)
            map.camera.pitch = 58
            map.camera.altitude = 1100
            session.pendingCenter = nil
        }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MiniMapView
        var routeID: ObjectIdentifier?
        var lastTheme: MapTheme?
        init(_ parent: MiniMapView) { self.parent = parent }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor(parent.session.theme.accent)
            renderer.lineWidth = 7
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}
