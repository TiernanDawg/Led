import SwiftUI

struct ContentView: View {
    @StateObject private var drive = DriveSession()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DrivingMapView(
                    coordinate: drive.coordinate,
                    heading: drive.heading,
                    cameraMode: drive.cameraMode
                )
                .ignoresSafeArea()

                Image(systemName: "car.fill")
                    .font(.system(size: drive.cameraMode == .cockpit ? 23 : 30, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.65), radius: 7, y: 3)
                    .offset(y: drive.cameraMode == .cockpit ? 34 : 8)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    header
                    Spacer()
                    if drive.cameraMode == .cockpit {
                        cockpitFrame
                    }
                    drivingControls
                }
                .padding(.top, geometry.safeAreaInsets.top + 8)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 10) + 8)
                .padding(.horizontal, 16)
            }
            .background(Color.black)
            .ignoresSafeArea()
        }
        .onAppear { drive.start() }
        .onDisappear { drive.stop() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("OPENROAD")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(2.4)
                HStack(spacing: 5) {
                    Circle()
                        .fill(drive.gpsEnabled ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(drive.gpsEnabled ? "GPS POSITION" : "FREE DRIVE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", drive.speedKPH))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    Text("KM/H")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(String(format: "%.2f KM", drive.distanceMeters / 1000))
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))

            Button {
                drive.changeCamera()
            } label: {
                Image(systemName: drive.cameraMode == .follow ? "view.3d" : "car.side")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 48)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
            }
            .accessibilityLabel("Switch camera")
        }
        .foregroundStyle(.white)
    }

    private var cockpitFrame: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("COCKPIT VIEW")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.5)
                Text("REAL-WORLD MAP")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Text(String(format: "%03.0f°", drive.heading))
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 12)
    }

    private var drivingControls: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    drive.enableGPS()
                } label: {
                    Label("USE GPS", systemImage: "location.fill")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Text(String(format: "%.5f, %.5f", drive.coordinate.latitude, drive.coordinate.longitude))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 12) {
                steeringButton(symbol: "arrow.left", label: "LEFT") {
                    drive.steer(-1)
                }
                steeringButton(symbol: "arrow.right", label: "RIGHT") {
                    drive.steer(1)
                }

                Spacer(minLength: 2)

                Button {
                    drive.toggleBrake()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text(drive.isBraking ? "BRAKING" : "BRAKE")
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(drive.isBraking ? Color.red.opacity(0.85) : Color.white.opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 21))
                    .overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.2)))
                }

                Button {
                    drive.toggleAcceleration()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20, weight: .black))
                        Text(drive.isAccelerating ? "COAST" : "DRIVE")
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.black)
                    .frame(width: 86, height: 76)
                    .background(drive.isAccelerating ? Color.green.opacity(0.9) : Color.white,
                                in: RoundedRectangle(cornerRadius: 21))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.16)))
    }

    private func steeringButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: 62, height: 76)
            .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.2)))
        }
    }
}

#Preview {
    ContentView()
}
