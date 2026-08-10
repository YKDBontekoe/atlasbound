import CoreLocation
import Foundation

/// Display-ready values for the selected-tile inspector.
struct TileIntelPresentation: Equatable {
    let state: TileState
    let distanceLabel: String?
    let structureName: String?

    init(
        tileID: String,
        tile: WorldTile?,
        tileEngine: TileEngine,
        playerLocation: CLLocation?,
        structures: [PlacedFactoryStructure]
    ) {
        state = tile?.state ?? .fogged
        if let coordinate = tileEngine.parseTileID(tileID), let playerLocation {
            let target = tileEngine.centerCoordinate(for: coordinate)
            let meters = playerLocation.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
            distanceLabel = meters < 1_000
                ? "\(Int(meters.rounded())) m away"
                : String(format: "%.1f km away", meters / 1_000)
        } else {
            distanceLabel = nil
        }
        structureName = structures.first(where: { $0.tileID == tileID })
            .flatMap { FactoryCatalog.byID[$0.definitionID]?.name }
    }
}
