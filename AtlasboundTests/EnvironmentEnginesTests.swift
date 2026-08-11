import XCTest
@testable import Atlasbound

final class EnvironmentEnginesTests: XCTestCase {
    private let tileEngine = TileEngine(option: .twenty)

    func testBiomeCellIsStableAcrossItsSixTileSpan() {
        let engine = BiomeCellEngine()
        let first = engine.cellID(for: TileCoordinate(q: -1, r: 5), tileEngine: tileEngine)
        let nearby = engine.cellID(for: TileCoordinate(q: -6, r: 0), tileEngine: tileEngine)
        XCTAssertEqual(first, nearby)
        XCTAssertTrue(first.hasPrefix("biome:20:"))
    }

    func testClassifierPrioritizesWaterAndKeepsRiverTrait() {
        let snapshot = BiomeClassifier().snapshot(
            cellID: "biome:20:0:0",
            signals: BiomeSignals(isRiver: true, isGreen: true)
        )
        XCTAssertEqual(snapshot.primary, .waterside)
        XCTAssertTrue(snapshot.has(.river))
    }

    func testEnvironmentalModifiersAreAlwaysMildlyBounded() {
        let storm = WeatherSnapshot(
            cellID: "weather:20:0:0", condition: .storm, temperatureC: 12,
            precipitationMM: 20, windKPH: 60, cloudCover: 100,
            observedAt: .now, expiresAt: .now.addingTimeInterval(3600)
        )
        let biome = BiomeSnapshot(cellID: "biome:20:0:0", primary: .waterside, traits: [.river], resolvedAt: .now, expiresAt: .now)
        let result = EnvironmentalModifierEngine().modifiers(biome: biome, weather: storm)
        XCTAssertGreaterThanOrEqual(result.solarPower, 0.8)
        XCTAssertLessThanOrEqual(result.windPower, 1.35)
        XCTAssertGreaterThan(result.waterYield, 1)
    }

    func testJourneyCompactionPreservesEndpointsAndDropsRepeatedTiles() {
        let points = [
            JourneyWaypoint(tileID: "hex:20:0:0", elapsedSeconds: 0),
            JourneyWaypoint(tileID: "hex:20:0:0", elapsedSeconds: 5),
            JourneyWaypoint(tileID: "hex:20:1:0", elapsedSeconds: 10),
        ]
        let result = JourneyEngine().compact(points)
        XCTAssertEqual(result.map(\.tileID), ["hex:20:0:0", "hex:20:1:0"])
        XCTAssertEqual(result.first?.elapsedSeconds, 0)
        XCTAssertEqual(result.last?.elapsedSeconds, 10)
    }
}
