import XCTest
@testable import Atlasbound

final class SkillTreeEngineTests: XCTestCase {
    private let engine = SkillTreeEngine()

    func testPointsEarnedMatchExplorerLevel() {
        XCTAssertEqual(engine.pointsEarned(explorerLevel: 1), 0)
        XCTAssertEqual(engine.pointsEarned(explorerLevel: 5), 4)
        XCTAssertEqual(engine.pointsEarned(explorerLevel: 50), 49)
    }

    func testRankUpCostsEscalateAndSpendTriangularPoints() {
        var state = SkillState.empty
        let root = "path_first_steps"

        let first = engine.applyRankUp(nodeID: root, state: &state, explorerLevel: 10)
        guard case .ranked(_, let rank1, let cost1) = first.outcome else {
            return XCTFail("Expected first rank-up")
        }
        XCTAssertEqual(rank1, 1)
        XCTAssertEqual(cost1, 1)
        XCTAssertEqual(engine.pointsSpent(state: state), 1)

        let second = engine.applyRankUp(nodeID: root, state: &state, explorerLevel: 10)
        guard case .ranked(_, let rank2, let cost2) = second.outcome else {
            return XCTFail("Expected second rank-up")
        }
        XCTAssertEqual(rank2, 2)
        XCTAssertEqual(cost2, 2)
        XCTAssertEqual(engine.pointsSpent(state: state), 3)
    }

    func testPrerequisitesBlockDeepNodes() {
        var state = SkillState.empty
        let denied = engine.canRankUp(
            nodeID: "path_fog_runner",
            state: state,
            explorerLevel: 20
        )
        guard case .denied = denied.outcome else {
            return XCTFail("Fog Runner should require First Steps")
        }

        _ = engine.applyRankUp(nodeID: "path_first_steps", state: &state, explorerLevel: 20)
        let allowed = engine.canRankUp(
            nodeID: "path_fog_runner",
            state: state,
            explorerLevel: 20
        )
        guard case .ranked = allowed.outcome else {
            return XCTFail("Fog Runner should unlock after First Steps")
        }
    }

    func testModifiersGrowWithDiminishingReturns() {
        var state = SkillState.empty
        for _ in 0..<5 {
            _ = engine.applyRankUp(nodeID: "path_first_steps", state: &state, explorerLevel: 100)
        }
        let mods = engine.modifiers(for: state)
        XCTAssertGreaterThan(mods.discoveryXPMultiplier, 1)
        XCTAssertLessThan(mods.discoveryXPMultiplier, 1.35)

        let empty = engine.modifiers(for: .empty)
        XCTAssertEqual(empty.discoveryXPMultiplier, 1)
    }

    func testSkillStorePersistsRanks() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-store-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SkillStore(fileURL: url)
        let result = store.rankUp(nodeID: "survey_careful_eye", explorerLevel: 5)
        guard case .ranked = result.outcome else {
            return XCTFail("Expected rank-up to succeed")
        }

        let reloaded = SkillStore(fileURL: url)
        XCTAssertEqual(reloaded.state.rank(of: "survey_careful_eye"), 1)
    }
}

final class UncappedExplorerProgressionTests: XCTestCase {
    private let engine = ExplorerProgressionEngine()

    func testClassicCurvePreservedThroughLevel50() {
        XCTAssertEqual(engine.xpRequired(forLevel: 1), 0)
        XCTAssertEqual(engine.xpRequired(forLevel: 2), 1_000)
        XCTAssertEqual(engine.xpRequired(forLevel: 50), 250 * 49 * 49 + 750 * 49)
    }

    func testLevelsContinuePastClassicArc() {
        let xp50 = engine.xpRequired(forLevel: 50)
        let xp51 = engine.xpRequired(forLevel: 51)
        XCTAssertGreaterThan(xp51, xp50)
        XCTAssertEqual(engine.level(forTotalXP: xp51), 51)
        XCTAssertEqual(engine.level(forTotalXP: engine.xpRequired(forLevel: 80)), 80)
    }

    func testProceduralTitlesPastAtlasLegend() {
        XCTAssertEqual(engine.title(forLevel: 40), "Atlas Legend")
        XCTAssertEqual(engine.title(forLevel: 50), "Atlas Legend")
        let title = engine.title(forLevel: 51)
        XCTAssertTrue(title.hasPrefix("Atlas Legend · "))
        XCTAssertNotEqual(title, engine.title(forLevel: 61))
    }

    func testAchievementTiersEscalate() {
        let low = engine.snapshot(
            metrics: ExplorerProgressionMetrics(
                totalXP: 0,
                discoveredTiles: 10,
                masteredTiles: 0,
                legendaryTiles: 0,
                totalVisits: 0,
                activeDays: 0,
                activitiesCompleted: 0,
                stampedActivityTypes: 0,
                expeditionsCompleted: 0
            )
        )
        XCTAssertTrue(low.achievements.contains { $0.id == "first-steps" && $0.isUnlocked })
        XCTAssertTrue(low.achievements.contains { $0.id == "first-steps-t2" && !$0.isUnlocked })

        let high = engine.snapshot(
            metrics: ExplorerProgressionMetrics(
                totalXP: 0,
                discoveredTiles: 100,
                masteredTiles: 0,
                legendaryTiles: 0,
                totalVisits: 0,
                activeDays: 0,
                activitiesCompleted: 0,
                stampedActivityTypes: 0,
                expeditionsCompleted: 0
            )
        )
        XCTAssertTrue(high.achievements.contains { $0.id == "first-steps-t2" && $0.isUnlocked })
    }
}

final class ProgressionSkillModifierTests: XCTestCase {
    func testDiscoveryXPScalesWithSkillModifiers() {
        let engine = ProgressionEngine()
        var tile = WorldTile(id: "hex:20:0:0", coordinate: TileCoordinate(q: 0, r: 0))
        var mods = SkillModifiers.identity
        mods.discoveryXPMultiplier = 1.5
        let result = engine.processVisit(tile: &tile, modifiers: mods)
        XCTAssertEqual(result.kind, .discovery)
        XCTAssertEqual(result.xpAwarded, 150)
        XCTAssertEqual(tile.masteryXP, 150)
    }

    func testSofterMasteryThresholdsAdvanceEarlier() {
        let engine = ProgressionEngine()
        var tile = WorldTile(id: "hex:20:1:0", coordinate: TileCoordinate(q: 1, r: 0))
        tile.state = .discovered
        tile.firstVisitedAt = .now
        tile.visitCount = 1
        tile.masteryXP = 140

        var mods = SkillModifiers.identity
        mods.masteryThresholdMultiplier = 0.8
        // explored threshold becomes 120 — already cleared by stored mastery.
        engine.applyMasteryPulse(tile: &tile, amount: 1, modifiers: mods)
        XCTAssertEqual(tile.state, .explored)
    }
}

final class ScoutCatalogExpansionTests: XCTestCase {
    func testRangerAndWaykeeperExtendHireChain() {
        XCTAssertEqual(ScoutCatalog.byID["cartographer_scout"]?.unlocksScoutID, "ranger_scout")
        XCTAssertEqual(ScoutCatalog.byID["ranger_scout"]?.explorerLevel, 28)
        XCTAssertEqual(ScoutCatalog.byID["waykeeper_scout"]?.tilesPerHour, 6)
        XCTAssertNil(ScoutCatalog.byID["waykeeper_scout"]?.unlocksScoutID)
    }

    func testFactoryResearchAddsLateTiers() {
        XCTAssertNotNil(FactoryResearchCatalog.byID["logistics_3"])
        XCTAssertNotNil(FactoryResearchCatalog.byID["automation_2"])
        XCTAssertNotNil(FactoryResearchCatalog.byID["power_3"])
        XCTAssertNotNil(FactoryResearchCatalog.byID["extraction_3"])
        XCTAssertTrue(
            FactoryResearchCatalog.byID["extraction_3"]!.prerequisiteIDs.contains("power_3")
        )
    }
}
