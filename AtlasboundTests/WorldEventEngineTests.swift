import XCTest
@testable import Atlasbound

final class WorldEventEngineTests: XCTestCase {
    private let engine = WorldEventEngine()
    private let tileEngine = TileEngine(tileSizeMeters: 20)

    func testUTCDayKeyIsStable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 28
        components.hour = 15
        let date = calendar.date(from: components)!
        XCTAssertEqual(WorldEventEngine.utcDayKey(for: date), "2026-07-28")
    }

    func testCatalogKindRotatesByDayOfYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents(year: 2026, month: 1, day: 1, hour: 12)
        let day1 = calendar.date(from: components)!
        components.day = 2
        let day2 = calendar.date(from: components)!
        components.day = 5
        let day5 = calendar.date(from: components)!

        XCTAssertEqual(WorldEventEngine.catalogKind(for: day1), .surge)
        XCTAssertEqual(WorldEventEngine.catalogKind(for: day2), .beaconRush)
        XCTAssertEqual(WorldEventEngine.catalogKind(for: day5), .surge)
    }

    func testEventWindowsDifferByKind() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 10))!

        let surge = WorldEventEngine.eventWindow(for: .surge, on: date)
        let circuit = WorldEventEngine.eventWindow(for: .hotspotCircuit, on: date)

        let surgeStartHour = calendar.component(.hour, from: surge.start)
        let surgeEndHour = calendar.component(.hour, from: surge.end)
        XCTAssertEqual(surgeStartHour, 14)
        XCTAssertEqual(surgeEndHour, 20)

        let circuitSpan = circuit.end.timeIntervalSince(circuit.start)
        XCTAssertEqual(circuitSpan, 86_400, accuracy: 1)
    }

    func testDailyHotspotsAreDeterministic() {
        let player = TileCoordinate(q: 0, r: 0)
        let first = engine.generateDailyHotspots(
            playerTile: player,
            discoveredTileIDs: [],
            tiles: [:],
            tileEngine: tileEngine,
            installationID: "install-a",
            dayKey: "2026-07-28"
        )
        let second = engine.generateDailyHotspots(
            playerTile: player,
            discoveredTileIDs: [],
            tiles: [:],
            tileEngine: tileEngine,
            installationID: "install-a",
            dayKey: "2026-07-28"
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, WorldEventConstants.dailyHotspotCount)
        XCTAssertEqual(Set(first).count, first.count)
    }

    func testHotspotsChangeWithDayKey() {
        let player = TileCoordinate(q: 0, r: 0)
        var tiles: [String: WorldTile] = [:]
        var discoveredIDs: Set<String> = []
        for axial in tileEngine.ring(around: player, radius: 1) {
            let id = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: tileEngine.tileSizeMeters)
            discoveredIDs.insert(id)
            tiles[id] = WorldTile(id: id, coordinate: axial, state: .discovered)
        }

        let a = engine.generateDailyHotspots(
            playerTile: player,
            discoveredTileIDs: discoveredIDs,
            tiles: tiles,
            tileEngine: tileEngine,
            installationID: "install-a",
            dayKey: "2026-07-28"
        )
        let b = engine.generateDailyHotspots(
            playerTile: player,
            discoveredTileIDs: discoveredIDs,
            tiles: tiles,
            tileEngine: tileEngine,
            installationID: "install-a",
            dayKey: "2026-07-29"
        )
        XCTAssertNotEqual(Set(a), Set(b))
    }

    func testEnsureStateCreatesLiveHotspotCircuit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Day-of-year for 2026-01-03 → index 2 → hotspotCircuit
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 12))!
        let state = engine.ensureState(
            state: .empty,
            playerTile: TileCoordinate(q: 0, r: 0),
            discoveredTileIDs: [],
            tiles: [:],
            tileEngine: tileEngine,
            installationID: "install",
            date: date
        )
        XCTAssertEqual(state.dayKey, "2026-01-03")
        XCTAssertFalse(state.dailyHotspotTileIDs.isEmpty)
        XCTAssertEqual(state.activeEvent?.kind, .hotspotCircuit)
        XCTAssertEqual(state.activeEvent?.hotspotTileIDs, state.dailyHotspotTileIDs)
    }

    func testHotspotCircuitVisitProgressAndCompletion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 12))!
        var state = engine.ensureState(
            state: .empty,
            playerTile: TileCoordinate(q: 0, r: 0),
            discoveredTileIDs: [],
            tiles: [:],
            tileEngine: tileEngine,
            installationID: "install",
            date: date
        )
        guard let active = state.activeEvent else {
            return XCTFail("Expected active hotspot circuit")
        }
        let required = active.tilesRequired
        XCTAssertGreaterThan(required, 0)

        var completed = false
        for tileID in active.hotspotTileIDs.prefix(required) {
            guard let axial = tileEngine.parseTileID(tileID) else { continue }
            let result = engine.processVisit(
                tileID: tileID,
                tile: axial,
                isNewDiscovery: true,
                state: state,
                at: date,
                tileEngine: tileEngine
            )
            state = result.state
            if result.award?.didComplete == true {
                completed = true
                XCTAssertEqual(result.award?.familiarityXPBonus, WorldEventConstants.completionFamiliarityXP)
            }
        }
        XCTAssertTrue(completed)
        XCTAssertTrue(state.completedEventSet.contains(active.id))
        XCTAssertEqual(state.lifetimeEventsCompleted, 1)
    }

    func testSurgeMultipliers() {
        let event = WorldEventInstance(
            id: "event:test:surge",
            kind: .surge,
            dayKey: "2026-07-28",
            title: "XP Surge",
            subtitle: "Boost",
            targetSectorID: nil,
            hotspotTileIDs: [],
            tilesRequired: 8,
            completionFamiliarityXP: 40,
            discoveryXPMultiplier: WorldEventConstants.surgeDiscoveryMultiplier,
            familiarityXPMultiplier: WorldEventConstants.surgeFamiliarityMultiplier,
            frontierScoreMultiplier: 1,
            windowStart: .distantPast,
            windowEnd: .distantFuture
        )
        let multipliers = engine.xpMultipliers(for: event)
        XCTAssertEqual(multipliers.discovery, 1.5, accuracy: 0.001)
        XCTAssertEqual(multipliers.familiarity, 1.5, accuracy: 0.001)
    }

    func testBeaconRushScoresOnlyTargetSectorDiscoveries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-01-02 → beaconRush
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12))!
        var state = engine.ensureState(
            state: .empty,
            playerTile: TileCoordinate(q: 0, r: 0),
            discoveredTileIDs: [],
            tiles: [:],
            tileEngine: tileEngine,
            installationID: "install",
            date: date
        )
        guard let active = state.activeEvent, let sectorID = active.targetSectorID else {
            return XCTFail("Expected beacon rush with sector")
        }
        guard let parsed = engine.sectorEngine.parseSectorID(sectorID) else {
            return XCTFail("Bad sector id")
        }
        let targetTile = engine.sectorEngine.centerTile(for: parsed.sector)
        let targetID = TileEngine.makeTileID(q: targetTile.q, r: targetTile.r, sizeMeters: 20)
        let outside = TileCoordinate(q: 0, r: 0)
        let outsideID = TileEngine.makeTileID(q: outside.q, r: outside.r, sizeMeters: 20)

        let miss = engine.processVisit(
            tileID: outsideID,
            tile: outside,
            isNewDiscovery: true,
            state: state,
            at: date,
            tileEngine: tileEngine
        )
        XCTAssertEqual(miss.state.eventProgressCount, 0)

        let hit = engine.processVisit(
            tileID: targetID,
            tile: targetTile,
            isNewDiscovery: true,
            state: miss.state,
            at: date,
            tileEngine: tileEngine
        )
        XCTAssertEqual(hit.state.eventProgressCount, 1)
        XCTAssertEqual(hit.award?.progressDelta, 1)
    }
}
