import CoreLocation
import Foundation

struct RoadEdge {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let length: Double
    let width: Float
    let speedLimit: Double
}

struct RoadVisual: Identifiable {
    let id: Int
    let x: Float
    let z: Float
    let length: Float
    let width: Float
    let yaw: Float
}

enum RoadNetworkError: Error {
    case invalidResponse
    case noRoadsFound
}

enum RoadNetwork {
    static func fetch(near center: CLLocationCoordinate2D) async throws -> [RoadEdge] {
        let query = "[out:json][timeout:25];way(around:900,\(center.latitude),\(center.longitude))[highway~\"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service|track|road)$\"][area!=yes];out geom;"
        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 35
        request.setValue("OpenRoadDrive/0.2 (iOS; OSM road graph)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else {
            throw RoadNetworkError.invalidResponse
        }

        var edges: [RoadEdge] = []
        for element in elements where (element["type"] as? String) == "way" {
            guard let geometry = element["geometry"] as? [[String: Any]],
                  let tags = element["tags"] as? [String: Any],
                  let highway = tags["highway"] as? String else { continue }

            let width = roadWidth(for: highway)
            let speed = speedLimit(tags["maxspeed"] as? String, highway: highway)
            var points: [CLLocationCoordinate2D] = []
            for item in geometry {
                guard let lat = item["lat"] as? CLLocationDegrees,
                      let lon = item["lon"] as? CLLocationDegrees else { continue }
                points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }

            for index in 0..<(max(0, points.count - 1)) {
                let a = points[index]
                let b = points[index + 1]
                let length = CLLocation(latitude: a.latitude, longitude: a.longitude)
                    .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                if length > 1 && length < 500 {
                    edges.append(RoadEdge(start: a, end: b, length: length, width: width, speedLimit: speed))
                }
            }
        }

        guard !edges.isEmpty else { throw RoadNetworkError.noRoadsFound }
        return edges
    }

    static func visuals(_ edges: [RoadEdge], origin: CLLocationCoordinate2D) -> [RoadVisual] {
        let earthRadius = 6_371_008.8
        let lat0 = origin.latitude * .pi / 180
        return edges.enumerated().map { index, edge in
            let ax = (edge.start.longitude - origin.longitude) * .pi / 180 * earthRadius * cos(lat0)
            let az = (edge.start.latitude - origin.latitude) * .pi / 180 * earthRadius
            let bx = (edge.end.longitude - origin.longitude) * .pi / 180 * earthRadius * cos(lat0)
            let bz = (edge.end.latitude - origin.latitude) * .pi / 180 * earthRadius
            let dx = bx - ax
            let dz = bz - az
            return RoadVisual(
                id: index,
                x: Float((ax + bx) / 2),
                z: Float((az + bz) / 2),
                length: Float(hypot(dx, dz)),
                width: edge.width,
                yaw: Float(atan2(dx, dz))
            )
        }
    }

    static func localPosition(_ coordinate: CLLocationCoordinate2D,
                              origin: CLLocationCoordinate2D) -> (x: Float, z: Float) {
        let radius = 6_371_008.8
        let lat0 = origin.latitude * .pi / 180
        let x = (coordinate.longitude - origin.longitude) * .pi / 180 * radius * cos(lat0)
        let z = (coordinate.latitude - origin.latitude) * .pi / 180 * radius
        return (Float(x), Float(z))
    }

    private static func roadWidth(for highway: String) -> Float {
        switch highway {
        case "motorway", "trunk": return 10.5
        case "primary", "secondary": return 8.0
        case "tertiary", "residential", "unclassified": return 6.5
        case "service", "living_street": return 4.5
        case "track": return 3.5
        default: return 5.5
        }
    }

    private static func speedLimit(_ value: String?, highway: String) -> Double {
        if let value, let number = Double(value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()),
           number > 0 {
            return value.lowercased().contains("mph") ? number * 1.60934 : number
        }
        switch highway {
        case "motorway": return 110
        case "trunk", "primary": return 80
        case "secondary", "tertiary": return 60
        case "residential", "living_street": return 30
        case "service", "track": return 20
        default: return 40
        }
    }
}
