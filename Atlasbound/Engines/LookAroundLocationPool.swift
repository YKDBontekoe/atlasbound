import Foundation
import CoreLocation
import MapKit

/// Generates random world locations with Apple Look Around coverage.
/// Single responsibility: target location generation for Pinpoint rounds.
struct LookAroundLocationPool: Sendable {

    /// Cities with known Look Around coverage — worldwide mode samples near these.
    static let seeds: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),  // San Francisco
        CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),   // New York
        CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),  // Los Angeles
        CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),    // London
        CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),     // Paris
        CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),   // Tokyo
        CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050),    // Berlin
        CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964),    // Rome
        CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038),    // Madrid
        CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),    // Moscow
        CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832),   // Toronto
        CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),  // Sydney
        CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),   // Seoul
        CLLocationCoordinate2D(latitude: 47.3769, longitude: 8.5417),     // Zurich
        CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686),    // Stockholm
        CLLocationCoordinate2D(latitude: 45.4215, longitude: -75.6972),   // Ottawa
        CLLocationCoordinate2D(latitude: 38.9072, longitude: -77.0369),   // Washington DC
        CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),   // Chicago
        CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901),     // Dordrecht
        CLLocationCoordinate2D(latitude: 52.3676, longitude: 4.9041),     // Amsterdam
        CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),     // Brussels
        CLLocationCoordinate2D(latitude: 53.3498, longitude: -6.2603),    // Dublin
        CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384),    // Helsinki
        CLLocationCoordinate2D(latitude: 45.7640, longitude: 4.8357),     // Lyon
        CLLocationCoordinate2D(latitude: 43.2965, longitude: 5.3698),     // Marseille
        CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708),    // Dubai
        CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198),    // Singapore
        CLLocationCoordinate2D(latitude: -22.9068, longitude: -43.1729),  // Rio de Janeiro
        CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),  // Vancouver
        CLLocationCoordinate2D(latitude: 35.6895, longitude: 51.3890),    // Tehran
    ]

    enum GenerationError: Error, LocalizedError {
        case insufficientHomeTurfCoverage
        case worldwideGenerationFailed

        var errorDescription: String? {
            switch self {
            case .insufficientHomeTurfCoverage:
                "Not enough Look Around coverage in your atlas yet."
            case .worldwideGenerationFailed:
                "Could not find enough Look Around locations. Try again."
            }
        }
    }

    // MARK: - Worldwide

    /// Generate round targets anywhere on Earth with Look Around validation.
    static func generateWorldwideTargets(count: Int = PinpointConstants.roundsPerGame) async throws -> [CLLocationCoordinate2D] {
        var targets: [CLLocationCoordinate2D] = []
        var usedSeedIndices = Set<Int>()
        let shuffledSeeds = Array(seeds.indices).shuffled()

        for round in 0..<count {
            guard let coordinate = await findWorldwideCoordinate(
                seedOrder: shuffledSeeds,
                usedSeedIndices: &usedSeedIndices,
                roundIndex: round,
                maxAttempts: 30
            ) else {
                throw GenerationError.worldwideGenerationFailed
            }
            targets.append(coordinate)
        }
        return targets
    }

    // MARK: - Home Turf

    /// Generate round targets from discovered tiles only (Look Around validated).
    static func generateHomeTurfTargets(
        discoveredTiles: [WorldTile],
        engine: TileEngine,
        count: Int = PinpointConstants.roundsPerGame
    ) async throws -> [CLLocationCoordinate2D] {
        guard discoveredTiles.count >= PinpointConstants.homeTurfMinTiles else {
            throw GenerationError.insufficientHomeTurfCoverage
        }

        var targets: [CLLocationCoordinate2D] = []
        var usedTileIDs = Set<String>()
        let shuffled = discoveredTiles.shuffled()

        for _ in 0..<count {
            guard let coordinate = await findHomeTurfCoordinate(
                tiles: shuffled,
                engine: engine,
                usedTileIDs: &usedTileIDs,
                maxAttempts: 40
            ) else {
                throw GenerationError.insufficientHomeTurfCoverage
            }
            targets.append(coordinate)
        }
        return targets
    }

    /// Bounding region for Home Turf guess map (discovered tile centers + padding).
    static func atlasRegion(for tiles: [WorldTile], engine: TileEngine) -> MKCoordinateRegion? {
        guard !tiles.isEmpty else { return nil }

        var minLat = 90.0
        var maxLat = -90.0
        var minLon = 180.0
        var maxLon = -180.0

        for tile in tiles {
            let center = engine.centerCoordinate(for: tile.coordinate)
            minLat = min(minLat, center.latitude)
            maxLat = max(maxLat, center.latitude)
            minLon = min(minLon, center.longitude)
            maxLon = max(maxLon, center.longitude)
        }

        let padding = 0.01
        let latDelta = max(maxLat - minLat + padding, 0.02)
        let lonDelta = max(maxLon - minLon + padding, 0.02)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }

    // MARK: - Private

    private static func findWorldwideCoordinate(
        seedOrder: [Int],
        usedSeedIndices: inout Set<Int>,
        roundIndex: Int,
        maxAttempts: Int
    ) async -> CLLocationCoordinate2D? {
        for attempt in 0..<maxAttempts {
            let seedIndex = seedOrder[(roundIndex + attempt) % seedOrder.count]
            if usedSeedIndices.contains(seedIndex), usedSeedIndices.count < seeds.count {
                continue
            }

            let coordinate = coordinateNearSeed(seeds[seedIndex])
            if await hasLookAround(at: coordinate) {
                usedSeedIndices.insert(seedIndex)
                return coordinate
            }
        }
        return nil
    }

    /// Small random offset (~3 km) around a seed city center.
    private static func coordinateNearSeed(_ seed: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let offsetLat = Double.random(in: -0.03...0.03)
        let offsetLon = Double.random(in: -0.03...0.03)
        return CLLocationCoordinate2D(
            latitude: max(-85, min(85, seed.latitude + offsetLat)),
            longitude: seed.longitude + offsetLon
        )
    }

    private static func findHomeTurfCoordinate(
        tiles: [WorldTile],
        engine: TileEngine,
        usedTileIDs: inout Set<String>,
        maxAttempts: Int
    ) async -> CLLocationCoordinate2D? {
        for attempt in 0..<maxAttempts {
            let tile = tiles[attempt % tiles.count]
            if usedTileIDs.contains(tile.id), usedTileIDs.count < tiles.count {
                continue
            }

            let center = engine.centerCoordinate(for: tile.coordinate)
            let offsetLat = Double.random(in: -0.002...0.002)
            let offsetLon = Double.random(in: -0.002...0.002)
            let coordinate = CLLocationCoordinate2D(
                latitude: max(-85, min(85, center.latitude + offsetLat)),
                longitude: center.longitude + offsetLon
            )

            if await hasLookAround(at: coordinate) {
                usedTileIDs.insert(tile.id)
                return coordinate
            }
        }
        return nil
    }

    private static func hasLookAround(at coordinate: CLLocationCoordinate2D) async -> Bool {
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        do {
            let scene = try await request.scene
            return scene != nil
        } catch {
            return false
        }
    }
}
