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
        var unusedCandidates = worldwideCandidateCoordinates().shuffled()

        while targets.count < count, !unusedCandidates.isEmpty {
            try Task.checkCancellation()
            let candidate = unusedCandidates.removeFirst()
            if await hasLookAround(at: candidate) {
                targets.append(candidate)
            }
        }

        guard targets.count == count else {
            throw GenerationError.worldwideGenerationFailed
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
            try Task.checkCancellation()
            guard let coordinate = await findHomeTurfCoordinate(
                tiles: shuffled,
                engine: engine,
                usedTileIDs: &usedTileIDs,
                maxAttempts: 12
            ) else {
                throw GenerationError.insufficientHomeTurfCoverage
            }
            targets.append(coordinate)
        }
        return targets
    }

    /// Bounding region for Home Turf guess map (discovered tile centers + padding).
    static func atlasRegion(for tiles: [WorldTile], engine: TileEngine) -> MKCoordinateRegion? {
        let centers = tiles.map { engine.centerCoordinate(for: $0.coordinate) }
        return StatsEngine.boundingRegion(
            tileCenters: centers,
            padding: .additive(padding: 0.01, minDelta: 0.02)
        )
    }

    // MARK: - Private

    private static func findWorldwideCoordinate(maxAttempts: Int) async -> CLLocationCoordinate2D? {
        for _ in 0..<maxAttempts {
            guard !Task.isCancelled else { return nil }
            let probe = randomLandCoordinate()

            if let coordinate = await findLookAroundFromMappedPlaces(center: probe, radius: 25_000) {
                return coordinate
            }

            guard let placemark = await reverseGeocodePlacemark(at: probe),
                  isLikelyUrban(placemark),
                  let anchor = placemark.location?.coordinate else {
                continue
            }

            if let coordinate = await findLookAroundNear(anchor, placemark: placemark) {
                return coordinate
            }
        }
        return nil
    }

    /// Try mapped places first, then the anchor, then nearby street offsets.
    private static func findLookAroundNear(
        _ anchor: CLLocationCoordinate2D,
        placemark: CLPlacemark? = nil
    ) async -> CLLocationCoordinate2D? {
        let mapItems = await nearbyMappedPlaces(anchor: anchor, placemark: placemark)
        if let coordinate = await firstLookAroundMapItemMatch(in: mapItems) {
            return coordinate
        }

        if await hasLookAround(at: anchor) {
            return anchor
        }

        if let coordinate = await firstLookAroundMatch(in: nearbyProbeCoordinates(around: anchor)) {
            return coordinate
        }

        return nil
    }

    /// Search Apple Maps for POIs near a probe — avoids geocoder rate limits.
    private static func findLookAroundFromMappedPlaces(
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async -> CLLocationCoordinate2D? {
        let poiRequest = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        guard let response = try? await MKLocalSearch(request: poiRequest).start(),
              !response.mapItems.isEmpty else {
            return nil
        }
        return await firstLookAroundMapItemMatch(in: response.mapItems)
    }

    private static func nearbyMappedPlaces(
        anchor: CLLocationCoordinate2D,
        placemark: CLPlacemark? = nil
    ) async -> [MKMapItem] {
        var items: [MKMapItem] = []

        let poiRequest = MKLocalPointsOfInterestRequest(center: anchor, radius: 5_000)
        if let response = try? await MKLocalSearch(request: poiRequest).start() {
            items.append(contentsOf: response.mapItems)
        }

        let resolvedPlacemark: CLPlacemark?
        if let placemark {
            resolvedPlacemark = placemark
        } else {
            resolvedPlacemark = await reverseGeocodePlacemark(at: anchor)
        }
        if let resolvedPlacemark,
           let query = localitySearchQuery(from: resolvedPlacemark) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: anchor,
                latitudinalMeters: 8_000,
                longitudinalMeters: 8_000
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
        await GeocodeLimiter.shared.reverseGeocode(at: coordinate)
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

    private static func firstLookAroundMapItemMatch(in items: [MKMapItem]) async -> CLLocationCoordinate2D? {
        let batchSize = 2
        var index = 0
        let candidates = items.shuffled()

        while index < candidates.count {
            let end = min(index + batchSize, candidates.count)
            let batch = Array(candidates[index..<end])

            if let match = await firstLookAroundMapItemMatchBatch(batch) {
                return match
            }

            index = end
        }

        return nil
    }

    private static func firstLookAroundMapItemMatchBatch(_ items: [MKMapItem]) async -> CLLocationCoordinate2D? {
        for item in items {
            if await hasLookAround(mapItem: item) {
                return item.placemark.coordinate
            }
        }
        return nil
    }

    private static func firstLookAroundMatch(in candidates: [CLLocationCoordinate2D]) async -> CLLocationCoordinate2D? {
        let batchSize = 2
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
        for coordinate in candidates {
            if await hasLookAround(at: coordinate) {
                return coordinate
            }
        }
        return nil
    }

    /// Land-biased random coordinate (avoids poles and open ocean more often than uniform sampling).
    private static func randomLandCoordinate() -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double.random(in: -55...55),
            longitude: Double.random(in: -180...180)
        )
    }

    /// Dense urban street locations. Every candidate is still validated with
    /// `MKLookAroundSceneRequest`; no round begins without a real Look Around scene.
    private static func worldwideCandidateCoordinates() -> [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: 52.3728, longitude: 4.8936),   // Amsterdam, Damrak
            CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),  // London, Whitehall
            CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945),   // Paris, Eiffel Tower
            CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // New York, Times Square
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),// San Francisco
            CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005), // Tokyo, Shibuya
            CLLocationCoordinate2D(latitude: 1.2903, longitude: 103.8519),  // Singapore, Marina Bay
            CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),// Sydney CBD
            CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964),  // Rome
            CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050),  // Berlin
            CLLocationCoordinate2D(latitude: 41.3851, longitude: 2.1734),   // Barcelona
            CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832)  // Toronto
        ]
    }

    /// Small offsets (~0.5–2 km) around an urban anchor to hit nearby mapped streets.
    private static func nearbyProbeCoordinates(around anchor: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let deltas = [-0.02, -0.015, -0.01, -0.005, 0.005, 0.01, 0.015, 0.02]
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
            if unique.count >= 20 { break }
        }

        return unique
    }
}

// MARK: - Test hooks

extension LookAroundLocationPool {
    static func isLikelyUrban(
        locality: String?,
        subLocality: String?,
        thoroughfare: String?,
        administrativeArea: String?,
        areasOfInterest: [String]?
    ) -> Bool {
        if locality != nil { return true }
        if subLocality != nil { return true }
        if thoroughfare != nil, administrativeArea != nil { return true }
        if let areas = areasOfInterest, !areas.isEmpty { return true }
        return false
    }

    static func isLikelyUrban(_ placemark: CLPlacemark) -> Bool {
        isLikelyUrban(
            locality: placemark.locality,
            subLocality: placemark.subLocality,
            thoroughfare: placemark.thoroughfare,
            administrativeArea: placemark.administrativeArea,
            areasOfInterest: placemark.areasOfInterest
        )
    }
}
