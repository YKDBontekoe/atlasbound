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

    func testFallbackTrailTargetsSpanMultiKilometerBands() {
        let anchor = TileCoordinate(q: 0, r: 0)
        let trail = engine.makeFallbackTrail(
            anchor: anchor,
            tileEngine: tileEngine,
            dayKey: "2026-08-03"
        )
        let distances = trail.stages.flatMap { [$0.directTarget.distanceMeters, $0.detourTarget.distanceMeters] }
        XCTAssertEqual(distances.count, TreasureConstants.stagesPerTrail * 2)
        XCTAssertGreaterThanOrEqual(distances.min() ?? 0, 1_000, "Nearest fallback should be ~1 km+")
        XCTAssertGreaterThanOrEqual(distances.max() ?? 0, 8_000, "Farthest fallback should reach ~8 km")
        for stage in trail.stages {
            XCTAssertGreaterThanOrEqual(
                stage.detourTarget.distanceMeters,
                stage.directTarget.distanceMeters
            )
        }
    }

    func testVaultTargetIsMultiKilometer() {
        let anchor = TileCoordinate(q: 2, r: -3)
        let vault = engine.makeVaultTarget(
            anchor: anchor,
            tileEngine: tileEngine,
            weekKey: "2026-W31"
        )
        XCTAssertGreaterThanOrEqual(vault.distanceMeters, 4_000)
        XCTAssertEqual(vault.distanceBand, .far)
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

    func testFartherBandNeverWorsensRelicRarityForFixedSeed() {
        let bands: [Double] = [0, 2_000, 5_000, 10_000]
        for index in 0..<80 {
            let seed = "distance-band-\(index)"
            var previous: RelicRarity = .common
            for meters in bands {
                let relic = engine.relic(
                    seed: seed,
                    landmarkName: "Test",
                    choice: .direct,
                    isVault: false,
                    distanceMeters: meters
                )
                XCTAssertGreaterThanOrEqual(relic.rarity, previous)
                previous = relic.rarity
            }
        }
    }

    func testCompletionXPScalesWithDistanceBand() {
        XCTAssertEqual(
            engine.completionFamiliarityXP(isVault: false, distanceMeters: 500),
            DistanceLootEngine.trailCompletionXP(for: .local)
        )
        XCTAssertEqual(
            engine.completionFamiliarityXP(isVault: false, distanceMeters: 9_000),
            DistanceLootEngine.trailCompletionXP(for: .expedition)
        )
        XCTAssertEqual(
            engine.completionFamiliarityXP(isVault: true, distanceMeters: 5_000),
            DistanceLootEngine.vaultCompletionXP(for: .far)
        )
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

final class DistanceLootEngineTests: XCTestCase {
    func testBandThresholds() {
        XCTAssertEqual(DistanceLootEngine.band(meters: 0), .local)
        XCTAssertEqual(DistanceLootEngine.band(meters: 1_499), .local)
        XCTAssertEqual(DistanceLootEngine.band(meters: 1_500), .mid)
        XCTAssertEqual(DistanceLootEngine.band(meters: 4_000), .far)
        XCTAssertEqual(DistanceLootEngine.band(meters: 8_000), .expedition)
    }

    func testHexApproximationUsesTileSize() {
        XCTAssertEqual(
            DistanceLootEngine.meters(hexDistance: 100, tileSizeMeters: 20),
            2_000
        )
        XCTAssertEqual(
            DistanceLootEngine.band(hexDistance: 400, tileSizeMeters: 20),
            .expedition
        )
    }

    func testTileOnRingKeepsExactHexDistance() {
        let center = TileCoordinate(q: 3, r: -2)
        for index in [0, 1, 17, 100, 249, 500, 1499] {
            let tile = DistanceLootEngine.tileOnRing(around: center, radius: 250, index: index)
            XCTAssertEqual(TileEngine.hexDistance(center, tile), 250)
        }
    }
}
