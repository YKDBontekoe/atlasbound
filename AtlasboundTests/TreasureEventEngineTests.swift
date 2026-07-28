import XCTest
@testable import Atlasbound

final class TreasureEventEngineTests: XCTestCase {
    private let engine = TreasureEventEngine()
    private let tileEngine = TileEngine(option: .twenty)

    func testFallbackTrailHasThreeStagesAndStableTargets() {
        let anchor = TileCoordinate(q: 10, r: -4)
        let first = engine.makeFallbackTrail(
            anchor: anchor,
            tileEngine: tileEngine,
            dayKey: "2026-07-28"
        )
        let second = engine.makeFallbackTrail(
            anchor: anchor,
            tileEngine: tileEngine,
            dayKey: "2026-07-28"
        )

        XCTAssertEqual(first.stages.count, TreasureConstants.stagesPerTrail)
        XCTAssertEqual(first.stages, second.stages)
        XCTAssertEqual(first.freeRerollsRemaining, 1)
        XCTAssertTrue(first.stages.allSatisfy(\.directTarget.isFallback))
    }

    func testDetourNeverProducesCommonRelic() {
        for index in 0..<100 {
            let relic = engine.relic(
                seed: "detour-\(index)",
                landmarkName: "Test",
                choice: .detour,
                isVault: false
            )
            XCTAssertGreaterThanOrEqual(relic.rarity, .uncommon)
        }
    }

    func testWeeklyVaultAlwaysProducesRareOrBetterRelic() {
        for index in 0..<100 {
            let relic = engine.relic(
                seed: "vault-\(index)",
                landmarkName: "Test",
                choice: .direct,
                isVault: true
            )
            XCTAssertGreaterThanOrEqual(relic.rarity, .rare)
        }
    }

    @MainActor
    func testTrailArrivalCannotBeCollectedTwice() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-treasure-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TreasureStore(fileURL: url)
        store.ensureTrail(anchor: TileCoordinate(q: 0, r: 0), tileEngine: tileEngine)
        let firstTarget = try XCTUnwrap(store.currentTarget)

        store.processVisitedTileIDs([firstTarget.tileID])
        XCTAssertNotNil(store.pendingEncounter)
        store.processVisitedTileIDs([firstTarget.tileID])
        XCTAssertEqual(store.dailyTrail?.currentStageIndex, 0)

        XCTAssertNil(store.resolveEncounter(choice: .direct))
        XCTAssertEqual(store.dailyTrail?.currentStageIndex, 1)
        store.processVisitedTileIDs([firstTarget.tileID])
        XCTAssertNil(store.pendingEncounter)
    }
}

