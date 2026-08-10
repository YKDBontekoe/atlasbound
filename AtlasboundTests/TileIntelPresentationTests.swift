import CoreLocation
import XCTest
@testable import Atlasbound

final class TileIntelPresentationTests: XCTestCase {
    func testFormatsNearbyDistanceAndFactoryStructureName() {
        let engine = TileEngine(tileSizeMeters: 20)
        let coordinate = CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901)
        let tileID = engine.tileID(for: coordinate)
        let definition = FactoryCatalog.definitions[0]
        let structure = PlacedFactoryStructure(
            tileID: tileID,
            definitionID: definition.id,
            tier: 1,
            inputBuffer: [:],
            outputBuffer: [:],
            selectedRecipeID: nil,
            recipeProgressMinutes: 0,
            extractedUnits: 0,
            priority: .normal,
            fueledMinutes: 0,
            placedAt: .now
        )

        let presentation = TileIntelPresentation(
            tileID: tileID,
            tile: nil,
            tileEngine: engine,
            playerLocation: CLLocation(
                latitude: engine.centerCoordinate(for: engine.axialCoordinate(for: coordinate)).latitude,
                longitude: engine.centerCoordinate(for: engine.axialCoordinate(for: coordinate)).longitude
            ),
            structures: [structure]
        )

        XCTAssertEqual(presentation.distanceLabel, "0 m away")
        XCTAssertEqual(presentation.structureName, definition.name)
        XCTAssertEqual(presentation.state, .fogged)
    }
}
