import XCTest
@testable import Atlasbound

final class TileMapStyleTests: XCTestCase {
    func testMasteryFillOpacityStepsUpTheLadder() {
        let opacities = [
            TileState.discovered,
            .explored,
            .surveyed,
            .mastered,
            .legendary
        ].map { $0.mapFillOpacity() }

        for index in 1..<opacities.count {
            XCTAssertGreaterThan(
                opacities[index],
                opacities[index - 1],
                "Mastery ladder fills should grow more solid with rank"
            )
        }
    }

    func testWeeklyChargeBoostsOpacityWithoutWashingOut() {
        let base = TileState.discovered.mapFillOpacity(isFreshDiscovery: false)
        let charged = TileState.discovered.mapFillOpacity(isFreshDiscovery: false, weeklyCharge: 2)
        XCTAssertGreaterThan(charged, base)
        XCTAssertLessThanOrEqual(charged, 0.72)
    }

    func testFreshDiscoveryBoostsEarlyMasteryFills() {
        XCTAssertGreaterThan(
            TileState.discovered.mapFillOpacity(isFreshDiscovery: true),
            TileState.discovered.mapFillOpacity()
        )
        XCTAssertGreaterThan(
            TileState.explored.mapFillOpacity(isFreshDiscovery: true),
            TileState.explored.mapFillOpacity()
        )
    }

    func testInteriorTilesHaveNoStrokeWidth() {
        XCTAssertEqual(
            TileState.discovered.mapStrokeWidth(isFreshDiscovery: false, isPerimeter: false),
            0
        )
        XCTAssertGreaterThan(
            TileState.discovered.mapStrokeWidth(isFreshDiscovery: false, isPerimeter: true),
            0
        )
    }

    func testPerimeterStrokeWidthStepsWithMastery() {
        XCTAssertLessThan(
            TileState.discovered.mapPerimeterStrokeWidth,
            TileState.legendary.mapPerimeterStrokeWidth
        )
        XCTAssertLessThan(
            TileState.explored.mapPerimeterStrokeWidth,
            TileState.mastered.mapPerimeterStrokeWidth
        )
    }

    func testSurveyedAndLegendaryUseDistinctBrandHues() {
        // Brand colors should differ from the shared teal/gold early-ladder hues.
        XCTAssertNotEqual(
            String(describing: TileState.surveyed.mapBrandColor),
            String(describing: TileState.explored.mapBrandColor)
        )
        XCTAssertNotEqual(
            String(describing: TileState.legendary.mapBrandColor),
            String(describing: TileState.mastered.mapBrandColor)
        )
    }
}
