# OpenRoad Drive

A native iOS, real-world free-drive prototype built around OpenStreetMap data and MapLibre Native.

## Current prototype

- Global, on-demand OSM-based vector map through OpenFreeMap.
- Geographic movement calculated in meters on a spherical Earth model (1:1 map coordinates).
- Accelerate/coast, braking, steering, speed and distance.
- Follow-camera and cockpit-style map camera modes.
- Optional GPS spawn/location support.
- Native SwiftUI interface and unsigned IPA build through GitHub Actions.

**Scope note:** this first milestone is a map-based driving prototype. The car is not yet constrained to the road graph, and this is not yet a full 3D vehicle/terrain simulator. Road snapping, route-following, 3D vehicle rendering, terrain and offline region downloads are later milestones. The map itself is geographically scaled; vehicle handling is arcade-style.

## Build an unsigned IPA

1. Open the **Actions** tab.
2. Run **Build iOS IPA** (or push a commit to `main`).
3. Download the `OpenRoadDrive-unsigned-ipa` artifact.
4. Extract the ZIP and sideload `OpenRoadDrive.ipa` with SideStore or another signer.

The IPA is unsigned; it must be signed on installation. No Apple Developer certificate is stored in this repository.

## Map data and attribution

MapLibre Native renders the OpenFreeMap Liberty style:

`https://tiles.openfreemap.org/styles/liberty`

OpenFreeMap uses OpenStreetMap-derived data. MapLibre's attribution control is retained in the map view. See [OpenFreeMap](https://openfreemap.org/), [OpenStreetMap copyright and ODbL](https://www.openstreetmap.org/copyright), and [MapLibre Native](https://github.com/maplibre/maplibre-native).

The public OpenFreeMap instance is used for normal on-demand map viewing, not bulk tile harvesting. For a production service with guaranteed availability, use a hosted provider or self-hosted tile infrastructure.

## Requirements

- Xcode 16.4 or newer
- XcodeGen
- iOS 16.0+
- Swift Package Manager

## Local build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -resolvePackageDependencies -project OpenRoadDrive.xcodeproj -scheme OpenRoadDrive
xcodebuild -project OpenRoadDrive.xcodeproj -scheme OpenRoadDrive -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/OpenRoadDrive.app Payload/
ditto -c -k --sequesterRsrc --keepParent Payload OpenRoadDrive.ipa
```

## License

Application source: MIT. Map data and map styles retain their respective upstream licenses and attribution requirements.
