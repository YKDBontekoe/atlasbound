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

    /// Minimum Haversine separation between Worldwide targets in one game.
    static let minimumWorldwideSeparationMeters: CLLocationDistance = 150_000

    // MARK: - Worldwide

    /// Generate round targets by sampling Look Around coverage regions dynamically.
    static func generateWorldwideTargets(count: Int = PinpointConstants.roundsPerGame) async throws -> [CLLocationCoordinate2D] {
        var targets: [CLLocationCoordinate2D] = []
        for _ in 0..<count {
            try Task.checkCancellation()
            let coordinate = try await generateWorldwideTarget(excluding: targets)
            targets.append(coordinate)
        }
        return targets
    }

    /// Find one Worldwide target sufficiently far from `excluding`.
    static func generateWorldwideTarget(
        excluding existing: [CLLocationCoordinate2D],
        minSeparationMeters: CLLocationDistance = minimumWorldwideSeparationMeters,
        maxAttempts: Int = 48
    ) async throws -> CLLocationCoordinate2D {
        for _ in 0..<maxAttempts {
            try Task.checkCancellation()
            guard let candidate = await findWorldwideCoordinate(maxAttempts: 4) else {
                continue
            }
            if isSufficientlyDistant(candidate, from: existing, minMeters: minSeparationMeters) {
                return candidate
            }
        }
        throw GenerationError.worldwideGenerationFailed
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
            let coordinate = try await generateHomeTurfTarget(
                discoveredTiles: shuffled,
                engine: engine,
                usedTileIDs: &usedTileIDs
            )
            targets.append(coordinate)
        }
        return targets
    }

    /// Find one Home Turf target, mutating `usedTileIDs` for dedupe across rounds.
    static func generateHomeTurfTarget(
        discoveredTiles: [WorldTile],
        engine: TileEngine,
        usedTileIDs: inout Set<String>,
        maxAttempts: Int = 12
    ) async throws -> CLLocationCoordinate2D {
        guard discoveredTiles.count >= PinpointConstants.homeTurfMinTiles else {
            throw GenerationError.insufficientHomeTurfCoverage
        }
        guard let coordinate = await findHomeTurfCoordinate(
            tiles: discoveredTiles.shuffled(),
            engine: engine,
            usedTileIDs: &usedTileIDs,
            maxAttempts: maxAttempts
        ) else {
            throw GenerationError.insufficientHomeTurfCoverage
        }
        return coordinate
    }

    /// Bounding region for Home Turf guess map (discovered tile centers + padding).
    static func atlasRegion(for tiles: [WorldTile], engine: TileEngine) -> MKCoordinateRegion? {
        let centers = tiles.map { engine.centerCoordinate(for: $0.coordinate) }
        return StatsEngine.boundingRegion(
            tileCenters: centers,
            padding: .additive(padding: 0.01, minDelta: 0.02)
        )
    }

    // MARK: - Coverage regions

    /// Approximate envelopes where Apple Look Around coverage exists.
    /// Used only as random sampling bounds — not tourist landmark seeds.
    struct CoverageRegion: Sendable, Equatable {
        let minLatitude: Double
        let maxLatitude: Double
        let minLongitude: Double
        let maxLongitude: Double

        var areaWeight: Double {
            max(0, maxLatitude - minLatitude) * max(0, maxLongitude - minLongitude)
        }

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            coordinate.latitude >= minLatitude
                && coordinate.latitude <= maxLatitude
                && coordinate.longitude >= minLongitude
                && coordinate.longitude <= maxLongitude
        }

        func randomCoordinate() -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: Double.random(in: minLatitude...maxLatitude),
                longitude: Double.random(in: minLongitude...maxLongitude)
            )
        }
    }

    static let lookAroundCoverageRegions: [CoverageRegion] = [
        // Contiguous United States
        CoverageRegion(minLatitude: 24.5, maxLatitude: 49.0, minLongitude: -124.8, maxLongitude: -66.9),
        // Japan
        CoverageRegion(minLatitude: 30.2, maxLatitude: 45.6, minLongitude: 129.0, maxLongitude: 145.9),
        // United Kingdom & Ireland
        CoverageRegion(minLatitude: 50.0, maxLatitude: 58.7, minLongitude: -10.5, maxLongitude: 1.8),
        // France (incl. Monaco corridor)
        CoverageRegion(minLatitude: 42.3, maxLatitude: 51.1, minLongitude: -5.0, maxLongitude: 8.3),
        // Italy
        CoverageRegion(minLatitude: 36.6, maxLatitude: 47.1, minLongitude: 6.6, maxLongitude: 18.6),
        // Spain & Portugal (incl. Andorra corridor)
        CoverageRegion(minLatitude: 36.0, maxLatitude: 43.8, minLongitude: -9.5, maxLongitude: 3.4),
        // Australia
        CoverageRegion(minLatitude: -43.7, maxLatitude: -10.6, minLongitude: 113.0, maxLongitude: 153.7),
        // New Zealand
        CoverageRegion(minLatitude: -47.3, maxLatitude: -34.3, minLongitude: 166.3, maxLongitude: 178.6),
        // Singapore
        CoverageRegion(minLatitude: 1.16, maxLatitude: 1.47, minLongitude: 103.60, maxLongitude: 104.10),
        // Southern Canada corridors
        CoverageRegion(minLatitude: 42.0, maxLatitude: 53.0, minLongitude: -123.5, maxLongitude: -59.5)
    ]

    static func randomCoverageProbe() -> CLLocationCoordinate2D {
        weightedRandomRegion().randomCoordinate()
    }

    static func isSufficientlyDistant(
        _ candidate: CLLocationCoordinate2D,
        from existing: [CLLocationCoordinate2D],
        minMeters: CLLocationDistance
    ) -> Bool {
        existing.allSatisfy { PinpointScoring.haversine(from: candidate, to: $0) >= minMeters }
    }

    // MARK: - Private

    private static func weightedRandomRegion() -> CoverageRegion {
        let regions = lookAroundCoverageRegions
        let total = regions.reduce(0.0) { $0 + $1.areaWeight }
        guard total > 0 else { return regions[0] }

        var ticket = Double.random(in: 0..<total)
        for region in regions {
            ticket -= region.areaWeight
            if ticket < 0 {
                return region
            }
        }
        return regions[regions.count - 1]
    }

    private static func findWorldwideCoordinate(maxAttempts: Int) async -> CLLocationCoordinate2D? {
        for _ in 0..<maxAttempts {
            guard !Task.isCancelled else { return nil }
            let probe = randomCoverageProbe()

            // POI-first: works for towns of any size and avoids geocoder throttling.
            if let coordinate = await findLookAroundFromMappedPlaces(center: probe, radius: 25_000) {
                return coordinate
            }

            // Soft fallback: reverse-geocode only when POI search was empty.
            if let placemark = await reverseGeocodePlacemark(at: probe),
               let anchor = placemark.location?.coordinate,
               let coordinate = await findLookAroundNear(anchor, placemark: placemark) {
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
