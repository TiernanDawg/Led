# MiniMap

MiniMap is a native iOS GPS navigation app with a game-inspired map experience. It replaces the former OpenRoadDrive prototype while retaining this repository and its GitHub Actions IPA build.

## Current implementation
- Native Apple MapKit map with 3D pitch, rotation, and user-location display.
- GPS permission handling and current-location recentering.
- Place/address search using Apple MapKit local search.
- Driving route calculation, route preview, distance, and estimated travel time using Apple MapKit Directions.
- Four visual presets: Sunset City, Gotham, Voxel, and Pixel Valley.
- Geographic positions and route data remain real-world accurate.
- Unsigned IPA packaging and validation through GitHub Actions.

## Theme status
The first implementation uses distinct native map presentation modes, camera pitch, route styling, and theme-specific interface treatments. It does not yet reproduce fully custom voxel or pixel-art 3D map rendering. Those require a dedicated custom renderer and remain a later milestone.

## Navigation and traffic limitations
This build calculates routes and previews them. It is not yet a complete turn-by-turn voice navigation system and does not include Waze-style crowdsourced reports or guaranteed live traffic. Apple Maps data availability and route estimates are provided by MapKit.

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
Map content, place search, and routing are provided by Apple MapKit. Their data terms and attribution apply.
