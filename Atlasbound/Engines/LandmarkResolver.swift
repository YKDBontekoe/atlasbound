import Foundation
import CoreLocation

protocol LandmarkResolving: Sendable {
    func targets(
        near coordinate: CLLocationCoordinate2D,
        tileEngine: TileEngine,
        count: Int
    ) async -> [LandmarkTarget]
}

/// Local fallback resolver. Named landmarks are now created by the authenticated
/// Supabase Edge Function using Mapbox Search; this keeps offline progression safe.
struct LandmarkResolver: LandmarkResolving, Sendable {
    func targets(
        near coordinate: CLLocationCoordinate2D,
        tileEngine: TileEngine,
        count: Int = TreasureConstants.stagesPerTrail * 2
    ) async -> [LandmarkTarget] {
        let anchor = tileEngine.axialCoordinate(for: coordinate)
        return TreasureEventEngine()
            .makeFallbackTrail(anchor: anchor, tileEngine: tileEngine, dayKey: TreasureEventEngine.localDayKey(for: .now))
            .stages
            .flatMap { [$0.directTarget, $0.detourTarget] }
            .prefix(max(0, count))
            .map { $0 }
    }
}
