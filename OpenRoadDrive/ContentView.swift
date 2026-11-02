import SwiftUI

struct ContentView: View {
    @StateObject private var drive = DriveSession()
    @State private var showLocationSearch = false
    @State private var locationQuery = ""

    private let accent = Color(red: 0.12, green: 0.82, blue: 0.98)
    private let panel = Color.black.opacity(0.66)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DrivingSceneView(drive: drive)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topHUD
                    Spacer(minLength: 10)
                    if drive.cameraMode == .cockpit {
                        cockpitHUD
                    }
                    bottomHUD
                }
                .padding(.top, geometry.safeAreaInsets.top + 7)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 8) + 7)
                .padding(.horizontal, 13)
            }
            .background(Color.black)
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear { drive.start() }
        .onDisappear { drive.stop() }
        .sheet(isPresented: $showLocationSearch) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose any real-world location")
                        .font(.headline)
                    TextField("City, landmark, or address", text: $locationQuery)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit {
                            drive.searchLocation(locationQuery)
                            showLocationSearch = false
                        }
                    Button {
                        drive.searchLocation(locationQuery)
                        showLocationSearch = false
                    } label: {
                        Text("LOAD WORLD").fontWeight(.bold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Roads and terrain load around the selected location. An internet connection is required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .navigationTitle("Go to")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showLocationSearch = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var topHUD: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(accent)
                    Text("OPENROAD")
                        .tracking(2.2)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(drive.roadReady ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(drive.roadStatus)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))

            VStack(spacing: 5) {
                Image(systemName: drive.controllerConnected ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(drive.controllerConnected ? accent : .white.opacity(0.55))
                Text(drive.controllerConnected ? "XBOX" : "PAD")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
            }
            .frame(width: 51, height: 55)
            .background(panel, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(drive.controllerConnected ? accent.opacity(0.55) : .white.opacity(0.12)))

            Button { showLocationSearch = true } label: {
                VStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                    Text("GO TO")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.6)
                }
                .frame(width: 55, height: 55)
                .background(panel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Button { drive.changeCamera() } label: {
                VStack(spacing: 5) {
                    Image(systemName: drive.cameraMode == .follow ? "car.side.fill" : "view.3d")
                        .font(.system(size: 17, weight: .semibold))
                    Text(drive.cameraMode == .follow ? "CHASE" : "COCKPIT")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.6)
                }
                .frame(width: 60, height: 55)
                .background(panel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    private var speedHUD: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.13), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(drive.speedKPH / 220, 1)))
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(String(format: "%.0f", drive.speedKPH))
                        .font(.system(size: 25, weight: .black, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("KM/H")
                        .font(.system(size: 7, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 7) {
                metricLine("DISTANCE", value: String(format: "%.2f KM", drive.distanceMeters / 1000))
                metricLine("HEADING", value: String(format: "%03.0f°", drive.heading))
                metricLine("SURFACE", value: drive.roadReady ? (drive.isOnRoad ? "ASPHALT" : "OFF ROAD") : "LOADING")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.13)))
    }

    private func metricLine(_ title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private var cockpitHUD: some View {
        HStack {
            Text("COCKPIT VIEW")
                .font(.system(size: 9, weight: .black))
                .tracking(1.2)
            Spacer()
            Text("© OpenStreetMap contributors")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(panel, in: Capsule())
        .padding(.bottom, 9)
    }

    private var bottomHUD: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                speedHUD
                Button { drive.enableGPS() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text("GPS")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                    }
                    .frame(width: 57, height: 92)
                    .background(panel, in: RoundedRectangle(cornerRadius: 17))
                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.13)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 9) {
                steeringButton("arrow.left", label: "LEFT") { drive.tapSteer(-1) }
                steeringButton("arrow.right", label: "RIGHT") { drive.tapSteer(1) }
                Spacer(minLength: 1)
                actionButton("BRAKE", symbol: "brake.warning", active: drive.isBraking, color: .red) {
                    drive.toggleBrake()
                }
                actionButton(drive.isAccelerating ? "COAST" : "DRIVE", symbol: "arrow.up", active: drive.isAccelerating, color: accent) {
                    drive.toggleAcceleration()
                }
                .disabled(!drive.roadReady)
                .opacity(drive.roadReady ? 1 : 0.45)
            }

            Text("© OpenStreetMap contributors  ·  Elevation: Copernicus DEM via Open-Meteo")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .frame(maxWidth: .infinity)

            if drive.controllerConnected {
                Text("XBOX: RT ACCELERATE  ·  LT BRAKE  ·  LEFT STICK STEER  ·  Y CAMERA")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.35)
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
            } else {
                Text("CONNECT AN XBOX / BLUETOOTH GAME CONTROLLER")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.45)
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.15)))
    }

    private func steeringButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19, weight: .black))
                Text(label).font(.system(size: 8, weight: .black)).tracking(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: 54, height: 66)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.17)))
        }
        .buttonStyle(.plain)
        .disabled(!drive.roadReady)
        .opacity(drive.roadReady ? 1 : 0.4)
    }

    private func actionButton(_ title: String, symbol: String, active: Bool,
                              color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19, weight: .black))
                Text(title).font(.system(size: 8, weight: .black)).tracking(0.8)
            }
            .foregroundStyle(active ? .black : .white)
            .frame(width: 68, height: 66)
            .background(active ? color : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(active ? color : .white.opacity(0.17)))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
