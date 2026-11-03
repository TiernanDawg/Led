# MiniMap

MiniMap is a native iOS GPS navigation app with a game-inspired map experience. It replaces the former OpenRoadDrive prototype while retaining this repository and its GitHub Actions IPA build.

## Implemented
- Native MapLibre vector map renderer using OpenFreeMap/OpenStreetMap tiles, with user-location display, compass, scale, and vector styling.
- GPS permission handling, location accuracy filtering, speed display, and recentering.
- Place and address search using Apple MapKit local search.
- Driving route calculation, alternate-route comparison, and route preview using Apple MapKit Directions.
- Best-effort route preference ranking for toll/highway avoidance using route names and maneuver text; this is heuristic and cannot guarantee avoidance.
- Spoken maneuver guidance using iOS text-to-speech.
- Live maneuver progression, route distance/time estimates, and off-route recalculation.
- Navigation start, pause, resume, and end controls.
- Background location/audio configuration for navigation and spoken guidance, subject to iOS authorization and real-device validation.
- Private local road-condition reports (accident, hazard, construction, stopped vehicle, police sighting) shown as map pins and stored on-device for up to 24 hours; reports are not uploaded or shared.
- Four visual presets: Sunset City, Gotham, Voxel, and Pixel Valley.
- Locally persisted saved destinations and the 20 most recent destinations, with clear-history and individual saved-place removal controls.
- Remaining-distance estimates that follow the current route-step geometry rather than only measuring straight-line distance to a step endpoint.
- Proximity-triggered spoken warnings for previously saved local road reports while navigation is active; reports expire after 24 hours and warnings are explicitly labeled as local/private.
- Automated unsigned IPA packaging and ZIP validation through GitHub Actions.

## Map theme status
MapLibre now renders real OpenStreetMap-based vector tiles from OpenFreeMap. The four presets currently select different real vector styles: Liberty (Sunset City), Dark (Gotham), Bright (Voxel), and Positron (Pixel Valley). These are meaningful cartographic style changes, but they are **not yet bespoke GTA/Gotham/voxel/pixel-art worlds**. True voxel geometry, pixel-art terrain, custom landmarks, and advanced 3D building treatments still require dedicated style assets and rendering work. Geographic positions and routing remain real-world data.

## Navigation and service limitations
- Route guidance is based on Apple MapKit Directions and its available maneuver instructions.
- Off-route detection and rerouting are implemented, but have not yet been field-tested across real drives and poor-GPS conditions.
- Local incident reports are private to this device. There is no crowdsourced hazard network, police-report network, community traffic, or guaranteed live traffic feed.
- No downloadable offline map packs or offline routing.
- Background location/audio modes are configured, but persistent navigation behavior still requires Always location permission and real-device validation; iOS may restrict background execution.
- CarPlay, destination sharing, cloud synchronization, and multi-user/community reporting are not yet implemented.
- Search results are cleared between queries to prevent stale destinations from being selected.\n- A successful CI build verifies compilation and IPA packaging; it does not replace on-device testing.

## Build an unsigned IPA
1. Open the Actions tab.
2. Run **Build MiniMap iOS IPA** or push a commit to main.
3. Download the **MiniMap-unsigned-ipa** artifact.
4. Extract the ZIP and sideload `MiniMap.ipa` with SideStore or another signer.

The IPA is unsigned and must be signed for installation.

## Requirements
- Xcode 27 hosted runner
- XcodeGen
- iOS 16.0+
- Swift / MapKit system frameworks

## Attribution
MapLibre Native renders OpenFreeMap vector styles based on OpenStreetMap data. OpenStreetMap data is available under the Open Database License (ODbL) and requires attribution. Search and driving directions currently use Apple MapKit services and remain subject to Apple terms. Open-Meteo provides elevation data for the separate 3D driving scene.
