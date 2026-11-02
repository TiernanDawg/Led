import CoreLocation
import Foundation

struct RoadEdge {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let length: Double
    let width: Float
    let speedLimit: Double
    var startElevation: Float = 0
    var endElevation: Float = 0
}

struct RoadVisual: Identifiable {
    let id: Int
    let startX: Float
    let startZ: Float
    let endX: Float
    let endZ: Float
    let startY: Float
    let endY: Float
    let width: Float
}

struct TerrainVisual {
    let columns: Int
    let rows: Int
    let spacing: Float
    let originX: Float
    let originZ: Float
    let elevations: [Float]
}

struct RoadData {
    let edges: [RoadEdge]
    let roads: [RoadVisual]
    let terrain: TerrainVisual
}

enum RoadNetworkError: Error {
    case invalidResponse
    case noRoadsFound
    case invalidElevation
}

enum RoadNetwork {
    private static let terrainSide = 9
    private static let terrainRadius = 1_100.0

    static func fetch(near center: CLLocationCoordinate2D) async throws -> RoadData {
        let query = "[out:json][timeout:25];way(around:1100,\(center.latitude),\(center.longitude))[highway~\"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service|track|road)$\"][area!=yes];out geom;"
        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        let endpoints = [
            "https://overpass-api.de/api/interpreter",
            "https://overpass.kumi.systems/api/interpreter",
            "https://overpass.nchc.org.tw/api/interpreter"
        ]
        var elements: [[String: Any]] = []
        for endpoint in endpoints {
            guard var endpointComponents = URLComponents(string: endpoint) else { continue }
            endpointComponents.queryItems = [URLQueryItem(name: "data", value: query)]
            guard let url = endpointComponents.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 16
            request.setValue("OpenRoadDrive/0.4 (iOS; OSM road graph)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let returnedElements = root["elements"] as? [[String: Any]] else { continue }
                elements = returnedElements
                break
            } catch {
                continue
            }
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

            for index in 0..<max(0, points.count - 1) {
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

        let terrain = await fetchTerrain(near: center)
        let elevatedEdges = edges.map { edge -> RoadEdge in
            var result = edge
            result.startElevation = terrainHeight(at: edge.start, origin: center, terrain: terrain)
            result.endElevation = terrainHeight(at: edge.end, origin: center, terrain: terrain)
            return result
        }
        let visuals = elevatedEdges.enumerated().map { index, edge in
            let a = localPosition(edge.start, origin: center)
            let b = localPosition(edge.end, origin: center)
            return RoadVisual(
                id: index,
                startX: a.x, startZ: a.z,
                endX: b.x, endZ: b.z,
                startY: edge.startElevation + 0.12,
                endY: edge.endElevation + 0.12,
                width: edge.width
            )
        }
        return RoadData(edges: elevatedEdges, roads: visuals, terrain: terrain)
    }

    static func localPosition(_ coordinate: CLLocationCoordinate2D,
                              origin: CLLocationCoordinate2D) -> (x: Float, z: Float) {
        let radius = 6_371_008.8
        let lat0 = origin.latitude * .pi / 180
        let x = (coordinate.longitude - origin.longitude) * .pi / 180 * radius * cos(lat0)
        let z = (coordinate.latitude - origin.latitude) * .pi / 180 * radius
        return (Float(x), Float(z))
    }

    private static func fetchTerrain(near center: CLLocationCoordinate2D) async -> TerrainVisual {
        let side = terrainSide
        let spacing = Float((terrainRadius * 2) / Double(side - 1))
        let latStep = (terrainRadius * 2) / Double(side - 1) / 111_320.0
        let lonScale = max(0.15, cos(center.latitude * .pi / 180))
        let lonStep = latStep / lonScale

        var coordinates: [(Double, Double)] = []
        for row in 0..<side {
            for column in 0..<side {
                let latitude = center.latitude + (Double(row) - Double(side - 1) / 2) * latStep
                let longitude = center.longitude + (Double(column) - Double(side - 1) / 2) * lonStep
                coordinates.append((latitude, longitude))
            }
        }

        var elevations = [Float](repeating: 0, count: coordinates.count)
        do {
            let batchSize = 100
            for start in stride(from: 0, to: coordinates.count, by: batchSize) {
                let end = min(start + batchSize, coordinates.count)
                let batch = Array(coordinates[start..<end])
                var url = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
                url.queryItems = [
                    URLQueryItem(name: "latitude", value: batch.map { String($0.0) }.joined(separator: ",")),
                    URLQueryItem(name: "longitude", value: batch.map { String($0.1) }.joined(separator: ","))
                ]
                var request = URLRequest(url: url.url!)
                request.timeoutInterval = 9
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let values = payload["elevation"] as? [NSNumber],
                      values.count == batch.count else { throw RoadNetworkError.invalidElevation }
                for (offset, value) in values.enumerated() {
                    elevations[start + offset] = value.floatValue
                }
            }
        } catch {
            // Keep roads playable when the elevation provider is unavailable.
            elevations = [Float](repeating: 0, count: coordinates.count)
        }

        return TerrainVisual(
            columns: side,
            rows: side,
            spacing: spacing,
            originX: -Float(terrainRadius),
            originZ: -Float(terrainRadius),
            elevations: elevations
        )
    }

    static func height(at coordinate: CLLocationCoordinate2D,
                       origin: CLLocationCoordinate2D,
                       terrain: TerrainVisual) -> Float {
        terrainHeight(at: coordinate, origin: origin, terrain: terrain)
    }

    private static func terrainHeight(at coordinate: CLLocationCoordinate2D,
                                      origin: CLLocationCoordinate2D,
                                      terrain: TerrainVisual) -> Float {
        let local = localPosition(coordinate, origin: origin)
        let column = max(0, min(Double(terrain.columns - 1),
                                (Double(local.x) - Double(terrain.originX)) / Double(terrain.spacing)))
        let row = max(0, min(Double(terrain.rows - 1),
                             (Double(local.z) - Double(terrain.originZ)) / Double(terrain.spacing)))
        let x0 = Int(floor(column)), z0 = Int(floor(row))
        let x1 = min(x0 + 1, terrain.columns - 1), z1 = min(z0 + 1, terrain.rows - 1)
        let tx = Float(column - Double(x0)), tz = Float(row - Double(z0))
        func value(_ x: Int, _ z: Int) -> Float { terrain.elevations[z * terrain.columns + x] }
        let a = value(x0, z0) * (1 - tx) + value(x1, z0) * tx
        let b = value(x0, z1) * (1 - tx) + value(x1, z1) * tx
        return a * (1 - tz) + b * tz
    }

    private static func roadWidth(for highway: String) -> Float {
        switch highway {
        case "motorway", "motorway_link", "trunk", "trunk_link": return 10.5
        case "primary", "primary_link", "secondary", "secondary_link": return 8.0
        case "tertiary", "tertiary_link", "residential", "unclassified": return 6.5
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
