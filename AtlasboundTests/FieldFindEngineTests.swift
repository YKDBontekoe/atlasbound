import XCTest
@testable import Atlasbound

final class FieldFindEngineTests: XCTestCase {
    private let engine = FieldFindEngine()
    private let tileEngine = TileEngine(option: .twenty)

    func testRollFindIsDeterministicForSameDayAndTile() {
        let tileID = TileEngine.makeTileID(q: 3, r: -1, sizeMeters: 20)
        let dayKey = "2026-07-29"
        let first = engine.rollFind(
            tileID: tileID,
            isDiscovery: true,
            dayKey: dayKey,
            claimedFindIDs: [],
            findsClaimedToday: 0
        )
        let second = engine.rollFind(
            tileID: tileID,
            isDiscovery: true,
            dayKey: dayKey,
            claimedFindIDs: [],
            findsClaimedToday: 0
        )
        XCTAssertEqual(first, second)
    }

    func testClaimedFindCannotRollAgain() {
        let tileID = TileEngine.makeTileID(q: 8, r: 2, sizeMeters: 20)
        let dayKey = "2026-07-29"
        guard let find = engine.rollFind(
            tileID: tileID,
            isDiscovery: true,
            dayKey: dayKey,
            claimedFindIDs: [],
            findsClaimedToday: 0
        ) else {
            // Not every tile yields; find a yielding tile.
            var yielded: FieldFind?
            for q in 0..<40 {
                let id = TileEngine.makeTileID(q: q, r: 0, sizeMeters: 20)
                if let find = engine.rollFind(
                    tileID: id,
                    isDiscovery: true,
                    dayKey: dayKey,
                    claimedFindIDs: [],
                    findsClaimedToday: 0
                ) {
                    yielded = find
                    break
                }
            }
            guard let yielded else {
                XCTFail("Expected at least one discovery drop in sample")
                return
            }
            let blocked = engine.rollFind(
                tileID: yielded.tileID,
                isDiscovery: true,
                dayKey: dayKey,
                claimedFindIDs: [yielded.id],
                findsClaimedToday: 1
            )
            XCTAssertNil(blocked)
            return
        }

        let blocked = engine.rollFind(
            tileID: tileID,
            isDiscovery: true,
            dayKey: dayKey,
            claimedFindIDs: [find.id],
            findsClaimedToday: 1
        )
        XCTAssertNil(blocked)
    }

    func testDailyCapBlocksFurtherFinds() {
        let tileID = TileEngine.makeTileID(q: 1, r: 1, sizeMeters: 20)
        let find = engine.rollFind(
            tileID: tileID,
            isDiscovery: true,
            dayKey: "2026-07-29",
            claimedFindIDs: [],
            findsClaimedToday: FieldFindConstants.maxFindsPerDay
        )
        XCTAssertNil(find)
    }

    func testDiscoveryYieldsMoreOftenThanRevisitAcrossSample() {
        let dayKey = "2026-07-29"
        var discoveryHits = 0
        var revisitHits = 0
        for q in 0..<200 {
            let tileID = TileEngine.makeTileID(q: q, r: -q, sizeMeters: 20)
            if engine.rollFind(
                tileID: tileID,
                isDiscovery: true,
                dayKey: dayKey,
                claimedFindIDs: [],
                findsClaimedToday: 0
            ) != nil {
                discoveryHits += 1
            }
            if engine.rollFind(
                tileID: tileID,
                isDiscovery: false,
                dayKey: dayKey,
                claimedFindIDs: [],
                findsClaimedToday: 0
            ) != nil {
                revisitHits += 1
            }
        }
        XCTAssertGreaterThan(discoveryHits, revisitHits)
        XCTAssertGreaterThan(discoveryHits, 10)
    }

    func testCanAssembleWhenInputsPresent() {
        let recipe = try! XCTUnwrap(ItemRecipes.all.first)
        let stacks = recipe.inputs.map { InventoryStack(itemID: $0.itemID, quantity: $0.quantity) }
        XCTAssertTrue(engine.canAssemble(recipe: recipe, stacks: stacks))
        XCTAssertFalse(engine.canAssemble(recipe: recipe, stacks: []))
    }

    func testSalvageYieldsMaterialsForUncommonPlus() {
        let tonicYield = engine.salvageYield(for: "familiarity_tonic", seed: 42)
        XCTAssertFalse(tonicYield.isEmpty)
        XCTAssertTrue(tonicYield.allSatisfy { ItemCatalog.definition(for: $0.itemID)?.category == .material })

        let mossYield = engine.salvageYield(for: "moss_scrap", seed: 42)
        XCTAssertTrue(mossYield.isEmpty)
    }

    func testFamiliarityBoostMultipliesAndConsumesCharge() {
        var effects = [
            ActiveItemEffect(
                id: UUID(),
                itemID: "familiarity_tonic",
                kind: .familiarityBoost,
                remainingCharges: 2,
                expiresAt: nil,
                startedAt: .now
            )
        ]
        let boosted = engine.modifiedFamiliarityXP(base: 20, effects: &effects)
        XCTAssertEqual(boosted, 30)
        XCTAssertEqual(effects.first?.remainingCharges, 1)
    }

    func testCatalogHasContentRichCoverage() {
        XCTAssertGreaterThanOrEqual(ItemCatalog.all.count, 40)
        XCTAssertEqual(ItemCatalog.materials.count, 14)
        XCTAssertEqual(ItemCatalog.components.count, 5)
        XCTAssertEqual(ItemCatalog.boosts.count, 5)
        XCTAssertEqual(ItemCatalog.charges.count, 5)
        XCTAssertEqual(ItemCatalog.assembled.count, 5)
        XCTAssertGreaterThanOrEqual(ItemRecipes.all.count, 11)
    }

    func testPreviewFindsRespectClaimedIDs() {
        let anchor = TileCoordinate(q: 0, r: 0)
        let dayKey = "2026-07-29"
        let previews = engine.previewFinds(
            around: anchor,
            radius: 5,
            tileEngine: tileEngine,
            dayKey: dayKey,
            claimedFindIDs: [],
            isTileDiscovered: { _ in false }
        )
        XCTAssertLessThanOrEqual(previews.count, FieldFindConstants.maxMapPreviews)
        if let first = previews.first {
            let blocked = engine.previewFinds(
                around: anchor,
                radius: 5,
                tileEngine: tileEngine,
                dayKey: dayKey,
                claimedFindIDs: [first.id],
                isTileDiscovered: { _ in false }
            )
            XCTAssertFalse(blocked.contains(where: { $0.id == first.id }))
        }
    }
}
