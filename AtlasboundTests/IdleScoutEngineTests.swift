import XCTest
@testable import Atlasbound

final class IdleScoutEngineTests: XCTestCase {
    private let engine = IdleScoutEngine()
    private let tileEngine = TileEngine(option: .twenty)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testHireUnlocksNextScoutInChain() {
        var state = IdleState.empty(at: Date(timeIntervalSince1970: 1_000))
        let apprentice = ScoutCatalog.byID["apprentice_scout"]!
        XCTAssertTrue(state.isUnlocked("apprentice_scout"))
        XCTAssertFalse(state.isUnlocked("pathfinder_scout"))

        engine.applyHire(definition: apprentice, state: &state, at: Date(timeIntervalSince1970: 1_100))
        XCTAssertTrue(state.isHired("apprentice_scout"))
        XCTAssertTrue(state.isUnlocked("pathfinder_scout"))
        XCTAssertFalse(state.isUnlocked("surveyor_scout"))
    }

    func testHireRequiresPrerequisiteAndMaterials() {
        var state = IdleState.empty()
        let denied = engine.canHire(
            scoutID: "pathfinder_scout",
            state: state,
            explorerLevel: 20,
            availableQuantity: { _ in 99 }
        )
        if case .denied(let reason) = denied {
            XCTAssertTrue(reason.contains("Apprentice"))
        } else {
            XCTFail("Expected pathfinder to stay locked")
        }

        engine.applyHire(definition: ScoutCatalog.byID["apprentice_scout"]!, state: &state)
        let missing = engine.canHire(
            scoutID: "pathfinder_scout",
            state: state,
            explorerLevel: 20,
            availableQuantity: { _ in 0 }
        )
        if case .denied = missing {
            // expected
        } else {
            XCTFail("Expected material gate")
        }
    }

    func testHomeDripRequiresHomeAndRespectsInterval() {
        var state = IdleState.empty()
        let none = engine.homeDrip(forMinutes: 29, hasHomeBase: true, state: &state)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(state.homeDripIntervalAccumulator, 29)

        let drip = engine.homeDrip(forMinutes: 1, hasHomeBase: true, state: &state)
        XCTAssertFalse(drip.isEmpty)
        XCTAssertEqual(state.homeDripIntervalAccumulator, 0)
        XCTAssertEqual(quantity("cobble_chip", in: drip), 1)

        let away = engine.homeDrip(forMinutes: 120, hasHomeBase: false, state: &state)
        XCTAssertTrue(away.isEmpty)
    }

    func testScoutDiscoveriesCapDailyAndPreferHomeFog() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var state = IdleState.empty(at: now.addingTimeInterval(-3 * 60 * 60))
        engine.applyHire(definition: ScoutCatalog.byID["apprentice_scout"]!, state: &state, at: now)
        engine.applyHire(definition: ScoutCatalog.byID["pathfinder_scout"]!, state: &state, at: now)
        // 1 + 2 = 3 tiles/hour → 9 tiles over 3h before daily cap.

        let homeSector = HexSectorEngine.makeSectorID(q: 0, r: 0, sizeMeters: 20)
        var territory = TerritoryState.empty
        territory.homeSectorID = homeSector
        territory.claims = [TerritoryClaim(sectorID: homeSector, claimedAt: now)]

        let dayKey = engine.dayKey(for: now, calendar: calendar)
        state.scoutDiscoveryDayKey = dayKey
        state.scoutDiscoveriesToday = IdleConstants.dailyScoutDiscoveryCap - 2

        let report = engine.advance(
            state: &state,
            to: now,
            territory: territory,
            discoveredTileIDs: [],
            tileEngine: tileEngine,
            calendar: calendar
        )

        XCTAssertEqual(report.scoutTileIDs.count, 2)
        XCTAssertEqual(state.scoutDiscoveriesToday, IdleConstants.dailyScoutDiscoveryCap)
        XCTAssertTrue(report.scoutTileIDs.allSatisfy { id in
            guard let axial = tileEngine.parseTileID(id) else { return false }
            return HexSectorEngine().sectorID(for: axial, sizeMeters: 20) == homeSector
        })
    }

    func testOfflineAdvanceCapsAtEightHours() {
        let start = Date(timeIntervalSince1970: 3_000_000_000)
        var state = IdleState.empty(at: start)
        state.homeDripIntervalAccumulator = 0
        let later = start.addingTimeInterval(20 * 60 * 60)
        var territory = TerritoryState.empty
        let homeSector = HexSectorEngine.makeSectorID(q: 0, r: 0, sizeMeters: 20)
        territory.homeSectorID = homeSector
        territory.claims = [TerritoryClaim(sectorID: homeSector, claimedAt: start)]

        let report = engine.advance(
            state: &state,
            to: later,
            territory: territory,
            discoveredTileIDs: [],
            tileEngine: tileEngine,
            calendar: calendar
        )
        XCTAssertEqual(report.simulatedMinutes, IdleConstants.maximumOfflineMinutes)
        // 480 / 30 = 16 home intervals → 16 cobble chips + 4 bonus intervals of sector dust.
        XCTAssertEqual(quantity("cobble_chip", in: report.homeDripItems), 16)
        XCTAssertEqual(quantity("sector_dust", in: report.homeDripItems), 4)
    }

    func testCircuitRewardClaimsOncePerDay() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86_400)
        var tiles = (0..<5).map { makeTile(q: $0, first: today, last: today) }
        tiles += (5..<12).map { makeTile(q: $0, first: yesterday, last: today) }
        let snapshot = DailyChallengeEngine().snapshot(tiles: tiles, at: today, calendar: calendar)
        XCTAssertTrue(snapshot.isComplete)

        var state = IdleState.empty(at: today)
        let first = engine.claimCircuitReward(snapshot: snapshot, state: &state)
        if case .claimed(let rewards) = first {
            XCTAssertFalse(rewards.isEmpty)
        } else {
            XCTFail("Expected first claim to succeed")
        }
        let second = engine.claimCircuitReward(snapshot: snapshot, state: &state)
        if case .denied = second {
            // expected
        } else {
            XCTFail("Expected second claim to fail")
        }
    }

    private func quantity(_ itemID: String, in amounts: [ItemAmount]) -> Int {
        amounts.first { $0.itemID == itemID }?.quantity ?? 0
    }

    private func makeTile(q: Int, first: Date, last: Date) -> WorldTile {
        WorldTile(
            id: TileEngine.makeTileID(q: q, r: 0, sizeMeters: 20),
            coordinate: TileCoordinate(q: q, r: 0),
            state: .discovered,
            masteryXP: 100,
            visitCount: first == last ? 1 : 2,
            firstVisitedAt: first,
            lastVisitedAt: last
        )
    }
}
