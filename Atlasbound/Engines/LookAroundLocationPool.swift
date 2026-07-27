import Foundation
import CoreLocation
import MapKit

/// Generates random world locations with Apple Look Around coverage.
/// Single responsibility: target location generation for Pinpoint rounds.
struct LookAroundLocationPool: Sendable {

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
        for _ in 0..<count {
            guard let coordinate = await findWorldwideCoordinate(maxAttempts: 25) else {
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

    private static func findWorldwideCoordinate(maxAttempts: Int) async -> CLLocationCoordinate2D? {
        for _ in 0..<maxAttempts {
            let coordinate = randomLandCoordinate()
            if await hasLookAround(at: coordinate) {
                return coordinate
            }
        }
        return nil
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

    /// Land-biased random coordinate (avoids poles).
    private static func randomLandCoordinate() -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double.random(in: -55...55),
            longitude: Double.random(in: -180...180)
        )
    }
}
