import CoreLocation
import MapLibre
import SwiftUI

struct DrivingMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let heading: Double
    let cameraMode: DriveCameraMode

    private let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.logoView.isHidden = false
        mapView.attributionButton.isHidden = false
        mapView.isRotateEnabled = false
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isPitchEnabled = false
        updateCamera(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        updateCamera(mapView)
    }

    private func updateCamera(_ mapView: MLNMapView) {
        let pitch: CGFloat = cameraMode == .follow ? 58 : 34
        let altitude: CLLocationDistance = cameraMode == .follow ? 310 : 125
        let camera = MLNMapCamera(
            lookingAtCenter: coordinate,
            altitude: altitude,
            pitch: pitch,
            heading: heading
        )
        mapView.setCamera(camera, animated: false)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {}
}
