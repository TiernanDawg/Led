# MiniMap

MiniMap is a native iOS GPS navigation app with a game-inspired map experience. It replaces the former OpenRoadDrive prototype while retaining this repository and its GitHub Actions IPA build.

## Implemented
- Native Apple MapKit map with 3D camera pitch, rotation, compass, scale, and user-location display.
- GPS permission handling, location accuracy filtering, speed display, and recentering.
- Place and address search using Apple MapKit local search.
- Driving route calculation and route preview using Apple MapKit Directions.
- Spoken maneuver guidance using iOS text-to-speech.
- Live maneuver progression, route distance/time estimates, and off-route recalculation.
- Navigation start, pause, resume, and end controls.
- Four visual presets: Sunset City, Gotham, Voxel, and Pixel Valley.
- Automated unsigned IPA packaging and ZIP validation through GitHub Actions.

## Map theme status
The current presets change Apple MapKit presentation modes, camera pitch, route color, and interface styling. They are **not yet fully custom game-style 3D worlds**. True voxel geometry, pixel-art terrain, and bespoke building/road rendering require a custom vector-map renderer and dedicated style assets. Geographic positions and routing remain real-world data.

## Navigation and service limitations
- Route guidance is based on Apple MapKit Directions and its available maneuver instructions.
- Off-route detection and rerouting are implemented, but have not yet been field-tested across real drives and poor-GPS conditions.
- No crowdsourced hazard reports, police reports, community traffic, or guaranteed live traffic feed.
- No downloadable offline map packs or offline routing.
- Background navigation behavior and persistent location operation have not yet been implemented or validated.
- Saved places, recent destinations, CarPlay, and destination sharing are not yet implemented.
- A successful CI build verifies compilation and IPA packaging; it does not replace on-device testing.

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
Map content, place search, and routing are provided by Apple MapKit. Apple's data terms and attribution apply.
