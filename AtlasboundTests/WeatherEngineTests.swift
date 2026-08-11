import XCTest
@testable import Atlasbound

final class WeatherEngineTests: XCTestCase {
    private let tileEngine = TileEngine(option: .twenty)

    func testWeatherCellsAreStableAndCoarse() {
        let cells = WeatherCellEngine()
        let first = cells.cellID(for: TileCoordinate(q: 1, r: 1), tileEngine: tileEngine)
        let nearby = cells.cellID(for: TileCoordinate(q: 10, r: 10), tileEngine: tileEngine)
        XCTAssertEqual(first, nearby)
        XCTAssertTrue(first.hasPrefix("weather:20:"))
    }

    func testConditionsAndModifiersReflectWeather() {
        let engine = WeatherEngine()
        XCTAssertEqual(engine.condition(temperatureC: 4, precipitationMM: 2, windKPH: 8), .rain)
        XCTAssertEqual(engine.condition(temperatureC: 36, precipitationMM: 0, windKPH: 4), .heat)
        XCTAssertEqual(engine.condition(temperatureC: 12, precipitationMM: 0, windKPH: 50), .wind)

        let storm = WeatherSnapshot(
            cellID: "weather:20:0:0",
            condition: .storm,
            temperatureC: 18,
            precipitationMM: 12,
            windKPH: 48,
            cloudCover: 100,
            observedAt: .now,
            expiresAt: .now.addingTimeInterval(3600)
        )
        let modifiers = engine.modifiers(for: storm)
        XCTAssertLessThan(modifiers.roadThroughput, 1)
        XCTAssertGreaterThan(modifiers.windPower, 1)
    }

    func testWeatherIsUsedByRenewableAndFarmCatalog() {
        XCTAssertEqual(FactoryCatalog.byID["solar_array"]?.kind, .renewable)
        XCTAssertEqual(FactoryCatalog.byID["field_plot"]?.kind, .farm)
        XCTAssertNotNil(FactoryRecipeCatalog.byID["grow_grain"])
        XCTAssertNotNil(ItemCatalog.definition(for: "treated_water"))
    }
}
