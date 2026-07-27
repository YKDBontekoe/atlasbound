import XCTest
@testable import Atlasbound

final class FrontierEngineTests: XCTestCase {
    private let engine = FrontierEngine()
    private let tileEngine = TileEngine(tileSizeMeters: 80)

    func testConnectedComponentsSplitIslands() {
        let a = TileCoordinate(q: 0, r: 0)
        let b = TileCoordinate(q: 1, r: 0)
        let c = TileCoordinate(q: 20, r: 20)
        let components = engine.connectedComponents(from: [a, b, c])
        XCTAssertEqual(components.count, 2)
    }

    func testBootstrapUsesPlayerSectorWhenEmpty() {
        let player = TileCoordinate(q: 5, r: -2)
        let anchor = engine.territoryAnchor(playerTile: player, discovered: [])
        XCTAssertEqual(anchor, [player])
    }

    func testFrontierNeighborsUndiscoveredTiles() {
        let discovered: Set<TileCoordinate> = [TileCoordinate(q: 0, r: 0)]
        let territory = discovered
        let frontier = engine.frontierTileCoordinates(territory: territory, discovered: discovered)
        XCTAssertEqual(frontier.count, 6)
    }

    func testWeeklyOffersAreDeterministic() {
        let installation = "test-installation"
        let week = "2026-W30"
        let first = engine.generateWeeklyOffers(
            playerTile: TileCoordinate(q: 0, r: 0),
            discoveredTileIDs: [],
            tiles: [:],
            tileEngine: tileEngine,
            installationID: installation,
            weekKey: week
        )
        let second = engine.generateWeeklyOffers(
            playerTile: TileCoordinate(q: 0, r: 0),
            discoveredTileIDs: [],
            tiles: [:],
            tileEngine: tileEngine,
            installationID: installation,
            weekKey: week
        )
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(Set(first.map(\.targetSectorID)).count, first.count)
    }

    func testRejectsHighlyDiscoveredSector() {
        let sector = engine.sectorEngine.sectorCoordinate(for: TileCoordinate(q: 18, r: 0))
        let members = engine.sectorEngine.tiles(in: sector)
        var tiles: [String: WorldTile] = [:]
        var discoveredIDs: Set<String> = []
        for tile in members {
            let id = TileEngine.makeTileID(q: tile.q, r: tile.r, sizeMeters: 80)
            discoveredIDs.insert(id)
            tiles[id] = WorldTile(
                id: id,
                coordinate: tile,
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        }
        let offers = engine.generateWeeklyOffers(
            playerTile: TileCoordinate(q: 0, r: 0),
            discoveredTileIDs: discoveredIDs,
            tiles: tiles,
            tileEngine: tileEngine,
            installationID: "seed",
            weekKey: "2026-W30"
        )
        XCTAssertFalse(offers.contains { $0.targetSectorID == engine.sectorEngine.sectorID(for: sector, sizeMeters: 80) })
    }

    func testScoringComponentsAndComboCap() {
        let origin = TileCoordinate(q: 0, r: 0)
        let territory: Set<TileCoordinate> = [origin]
        let targetSector = engine.sectorEngine.sectorAt(
            distance: 1,
            from: engine.sectorEngine.sectorCoordinate(for: origin),
            directionIndex: 0
        )
        let targetID = engine.sectorEngine.sectorID(for: targetSector, sizeMeters: 80)
        let offer = ExpeditionOffer(
            id: "expedition:test",
            difficulty: .scout,
            targetSectorID: targetID,
            targetSectorDistance: 1,
            directionIndex: 0,
            tilesRequired: 12,
            completionBonus: 500
        )
        let targetTile = engine.sectorEngine.tiles(in: targetSector).min {
            TileEngine.hexDistance($0, origin) < TileEngine.hexDistance($1, origin)
        }!
        let path = TileEngine.hexLine(from: origin, to: targetTile)
        let discovered = Set(path.dropLast()).union(territory)
        let tileID = TileEngine.makeTileID(q: targetTile.q, r: targetTile.r, sizeMeters: 80)

        var combo = FrontierComboState.empty
        for _ in 0..<12 {
            combo = engine.advanceCombo(current: combo, qualifyingTile: true, at: .now)
        }
        XCTAssertEqual(combo.multiplier, 2.0)

        let expiredCombo = engine.advanceCombo(
            current: FrontierComboState(count: 5, expiresAt: Date(timeIntervalSinceNow: -10)),
            qualifyingTile: true,
            at: .now
        )
        XCTAssertEqual(expiredCombo.count, 1)

        let result = engine.scoreDiscovery(
            tileID: tileID,
            tile: targetTile,
            isNewDiscovery: true,
            activeOffer: offer,
            territory: territory,
            discovered: discovered,
            targetSectorDiscoveredCount: 11,
            connectionBonusesAwarded: [],
            combo: combo,
            tileEngine: tileEngine,
            at: .now
        )
        XCTAssertNotNil(result.award)
        XCTAssertEqual(result.award?.basePoints, FrontierEngine.baseTilePoints)
        XCTAssertEqual(result.award?.sectorBonus, FrontierEngine.targetSectorBonus)
        XCTAssertEqual(result.completionBonus, offer.completionBonus)
    }

    func testConnectionBonusIsIdempotent() {
        let origin = TileCoordinate(q: 0, r: 0)
        let territory: Set<TileCoordinate> = [origin]
        let targetSector = engine.sectorEngine.sectorAt(
            distance: 1,
            from: engine.sectorEngine.sectorCoordinate(for: origin),
            directionIndex: 0
        )
        let targetID = engine.sectorEngine.sectorID(for: targetSector, sizeMeters: 80)
        let offer = ExpeditionOffer(
            id: "expedition:connect",
            difficulty: .scout,
            targetSectorID: targetID,
            targetSectorDistance: 1,
            directionIndex: 0,
            tilesRequired: 12,
            completionBonus: 500
        )
        let entryTile = engine.sectorEngine.tiles(in: targetSector).min {
            TileEngine.hexDistance($0, origin) < TileEngine.hexDistance($1, origin)
        }!
        let path = TileEngine.hexLine(from: origin, to: entryTile)
        let discovered = Set(path.dropLast()).union(territory)
        let tileID = TileEngine.makeTileID(q: entryTile.q, r: entryTile.r, sizeMeters: 80)

        let first = engine.scoreDiscovery(
            tileID: tileID,
            tile: entryTile,
            isNewDiscovery: true,
            activeOffer: offer,
            territory: territory,
            discovered: discovered,
            targetSectorDiscoveredCount: 0,
            connectionBonusesAwarded: [],
            combo: .empty,
            tileEngine: tileEngine,
            at: .now
        )
        XCTAssertTrue(first.connectionBonusAwarded)

        let second = engine.scoreDiscovery(
            tileID: tileID,
            tile: entryTile,
            isNewDiscovery: true,
            activeOffer: offer,
            territory: territory,
            discovered: discovered.union([entryTile]),
            targetSectorDiscoveredCount: 0,
            connectionBonusesAwarded: [offer.id],
            combo: .empty,
            tileEngine: tileEngine,
            at: .now
        )
        XCTAssertFalse(second.connectionBonusAwarded)
    }

    func testISOWeekKeyFormat() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        XCTAssertEqual(FrontierEngine.isoWeekKey(for: date, calendar: calendar), "2026-W31")
    }
}
