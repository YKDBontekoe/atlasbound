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
            guard let coordinate = await findWorldwideCoordinate(maxAttempts: 40) else {
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

        let resolvedPlacemark = placemark ?? await reverseGeocodePlacemark(at: anchor)
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

// MARK: - Geocode rate limiting

/// CLGeocoder is rate-limited; serialize requests to avoid silent failures during Pinpoint prep.
private actor GeocodeLimiter {
    static let shared = GeocodeLimiter()

    private var lastRequest = Date.distantPast
    private let minimumInterval: TimeInterval = 0.15

    func reverseGeocode(at coordinate: CLLocationCoordinate2D) async -> CLPlacemark? {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minimumInterval {
            let delay = minimumInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequest = Date()

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
