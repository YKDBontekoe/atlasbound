import Foundation
import CoreLocation

/// Turns an active, real landmark trail target into a concise map quest.
/// The engine is presentation-only; the TreasureStore remains the sole owner
/// of destination completion and relic rewards.
struct LandmarkQuestEngine: Sendable {
    func makeQuest(
        target: LandmarkTarget?,
        playerCoordinate: CLLocationCoordinate2D?,
        tileEngine: TileEngine
    ) -> LandmarkQuest? {
        guard let target,
              let axial = tileEngine.parseTileID(target.tileID) else {
            return nil
        }
        let targetCoordinate = tileEngine.centerCoordinate(for: axial)
        let distance = playerCoordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude))
        } ?? target.distanceMeters
        return LandmarkQuest(
            target: target,
            theme: theme(for: target),
            distanceMeters: max(0, distance)
        )
    }

    func theme(for target: LandmarkTarget) -> LandmarkQuestTheme {
        let descriptor = "\(target.category) \(target.name) \(target.clue)".lowercased()
        if descriptor.contains("water") || descriptor.contains("river") || descriptor.contains("canal") || descriptor.contains("bridge") || descriptor.contains("harbor") {
            return .waterside
        }
        if descriptor.contains("park") || descriptor.contains("garden") || descriptor.contains("forest") || descriptor.contains("green") || descriptor.contains("trail") {
            return .greenspace
        }
        if descriptor.contains("museum") || descriptor.contains("historic") || descriptor.contains("history") || descriptor.contains("monument") || descriptor.contains("church") {
            return .heritage
        }
        return .city
    }
}
