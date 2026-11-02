import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var nav = NavigationSession()
    @State private var showingSearch = false
    @State private var query = ""

    private let themes = MapTheme.allCases

    var body: some View {
        ZStack {
            MiniMapView(session: nav)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                Spacer()
                if let route = nav.route {
                    routeBanner(route)
                }
                themePicker
                bottomPanel
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color.black)
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search places or addresses", text: $query)
                            .submitLabel(.search)
                            .onSubmit { nav.search(query); showingSearch = false }
                    }
                    .padding(14)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    Button("Search") { nav.search(query); showingSearch = false }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    if nav.isSearching { ProgressView("Searching…") }
                    if let error = nav.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if !nav.results.isEmpty {
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
                    Spacer()
                }
                .padding()
                .navigationTitle("Find a destination")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingSearch = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { nav.start() }
        .onDisappear { nav.stop() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("MiniMap").font(.system(size: 23, weight: .black, design: .rounded))
                Text(nav.status).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button { showingSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
            }
            Button { nav.centerOnUser() } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 20))
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MAP WORLDS").font(.system(size: 10, weight: .black)).tracking(1.4)
                Spacer()
                Text(nav.theme.subtitle).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(themes) { theme in
                        Button { nav.theme = theme } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: theme.symbol).font(.system(size: 18, weight: .bold))
                                Text(theme.title).font(.system(size: 10, weight: .black))
                            }
                            .foregroundStyle(nav.theme == theme ? .black : .white)
                            .frame(width: 83, height: 62)
                            .background(nav.theme == theme ? theme.accent : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
    }

    private var bottomPanel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nav.route == nil ? "READY TO EXPLORE" : "ROUTE ACTIVE")
                    .font(.system(size: 9, weight: .black)).tracking(1)
                    .foregroundStyle(.white.opacity(0.65))
                Text(nav.route.map { String(format: "%.1f mi · %d min", $0.distance / 1609.344, Int($0.expectedTravelTime / 60)) } ?? "Search anywhere to get directions")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            Spacer()
            if nav.route != nil {
                Button("END") { nav.clearRoute() }
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background(.red.opacity(0.85), in: Capsule())
            } else {
                Button("SEARCH") { showingSearch = true }
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background(nav.theme.accent, in: Capsule())
                    .foregroundStyle(.black)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
    }

    private func routeBanner(_ route: MKRoute) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Route preview").font(.system(size: 12, weight: .black))
                Text("\(route.name.isEmpty ? "Fastest available route" : route.name) · \(String(format: "%.1f mi", route.distance / 1609.344))")
                    .font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(13)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
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
        map.pointOfInterestFilter = .includingAll
        map.camera.pitch = 58
        map.camera.altitude = 1100
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        map.mapType = session.theme.mapType
        if let route = session.route, context.coordinator.routeID != ObjectIdentifier(route) {
            map.removeOverlays(map.overlays)
            map.addOverlay(route.polyline)
            context.coordinator.routeID = ObjectIdentifier(route)
            map.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 160, left: 45, bottom: 260, right: 45), animated: true)
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
