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
            guard let coordinate = await findWorldwideCoordinate(maxAttempts: 20) else {
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
            let probe = randomLandCoordinate()
            guard let anchor = await urbanAnchor(near: probe) else { continue }
            if let coordinate = await findLookAroundNear(anchor) {
                return coordinate
            }
        }
        return nil
    }

    /// Reverse-geocode a random probe and keep it only when it lands in a populated area.
    private static func urbanAnchor(near coordinate: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        guard let placemark = await reverseGeocodePlacemark(at: coordinate),
              isLikelyUrban(placemark),
              let anchor = placemark.location?.coordinate else {
            return nil
        }
        return anchor
    }

    /// Try the anchor, nearby street offsets, then nearby mapped places.
    private static func findLookAroundNear(_ anchor: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        if await hasLookAround(at: anchor) {
            return anchor
        }

        if let coordinate = await firstLookAroundMatch(in: nearbyProbeCoordinates(around: anchor)) {
            return coordinate
        }

        let mapItems = await nearbyMappedPlaces(anchor: anchor)
        for item in mapItems {
            if await hasLookAround(mapItem: item) {
                return item.placemark.coordinate
            }
        }

        return nil
    }

    private static func nearbyMappedPlaces(anchor: CLLocationCoordinate2D) async -> [MKMapItem] {
        var items: [MKMapItem] = []

        let poiRequest = MKLocalPointsOfInterestRequest(center: anchor, radius: 2_000)
        if let response = try? await MKLocalSearch(request: poiRequest).start() {
            items.append(contentsOf: response.mapItems)
        }

        if let placemark = await reverseGeocodePlacemark(at: anchor),
           let query = localitySearchQuery(from: placemark) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: anchor,
                latitudinalMeters: 5_000,
                longitudinalMeters: 5_000
            )
            request.resultTypes = [.address, .pointOfInterest]
            if let response = try? await MKLocalSearch(request: request).start() {
                items.append(contentsOf: response.mapItems)
            }
        }

        return deduplicatedMapItems(items)
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
            if let coordinate = await findLookAroundNear(center) {
                usedTileIDs.insert(tile.id)
                return coordinate
            }
        }
        return nil
    }

    private static func reverseGeocodePlacemark(at coordinate: CLLocationCoordinate2D) async -> CLPlacemark? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            return placemarks.first
        } catch {
            return nil
        }
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

    private static func hasLookAround(mapItem: MKMapItem) async -> Bool {
        let request = MKLookAroundSceneRequest(mapItem: mapItem)
        do {
            let scene = try await request.scene
            return scene != nil
        } catch {
            return false
        }
    }

    private static func firstLookAroundMatch(in candidates: [CLLocationCoordinate2D]) async -> CLLocationCoordinate2D? {
        let batchSize = 6
        var index = 0

        while index < candidates.count {
            let end = min(index + batchSize, candidates.count)
            let batch = Array(candidates[index..<end])

            if let match = await firstLookAroundMatchBatch(batch) {
                return match
            }

            index = end
        }

        return nil
    }

    private static func firstLookAroundMatchBatch(_ candidates: [CLLocationCoordinate2D]) async -> CLLocationCoordinate2D? {
        await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            for coordinate in candidates {
                group.addTask {
                    await hasLookAround(at: coordinate) ? coordinate : nil
                }
            }

            for await result in group {
                if let result {
                    return result
                }
            }
            return nil
        }
    }

    /// Land-biased random coordinate (avoids poles and open ocean more often than uniform sampling).
    private static func randomLandCoordinate() -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double.random(in: -55...55),
            longitude: Double.random(in: -180...180)
        )
    }

    /// Small offsets (~0.5–2 km) around an urban anchor to hit nearby mapped streets.
    private static func nearbyProbeCoordinates(around anchor: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let deltas = [-0.015, -0.01, -0.005, 0.005, 0.01, 0.015]
        var candidates: [CLLocationCoordinate2D] = []

        for deltaLat in deltas {
            for deltaLon in deltas where deltaLat != 0 || deltaLon != 0 {
                candidates.append(
                    CLLocationCoordinate2D(
                        latitude: max(-85, min(85, anchor.latitude + deltaLat)),
                        longitude: anchor.longitude + deltaLon
                    )
                )
            }
        }

        return candidates.shuffled()
    }

    private static func localitySearchQuery(from placemark: CLPlacemark) -> String? {
        let parts = [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    private static func deduplicatedMapItems(_ items: [MKMapItem]) -> [MKMapItem] {
        var seen = Set<String>()
        var unique: [MKMapItem] = []

        for item in items.shuffled() {
            let coordinate = item.placemark.coordinate
            let key = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
            guard seen.insert(key).inserted else { continue }
            unique.append(item)
            if unique.count >= 12 { break }
        }

        return unique
    }
}

// MARK: - Test hooks

extension LookAroundLocationPool {
    static func isLikelyUrban(_ placemark: CLPlacemark) -> Bool {
        if placemark.locality != nil { return true }
        if placemark.subLocality != nil { return true }
        if placemark.thoroughfare != nil, placemark.administrativeArea != nil { return true }
        if let areas = placemark.areasOfInterest, !areas.isEmpty { return true }
        return false
    }
}
