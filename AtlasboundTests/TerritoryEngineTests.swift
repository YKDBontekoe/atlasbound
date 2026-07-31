import XCTest
@testable import Atlasbound

final class TerritoryEngineTests: XCTestCase {
    private let engine = TerritoryEngine()
    private let sectorEngine = HexSectorEngine()
    private let tileEngine = TileEngine(tileSizeMeters: 20)

    func testClaimRequiresCompletionAndProximity() {
        let sector = SectorCoordinate(q: 0, r: 0)
        let sectorID = sectorEngine.sectorID(for: sector, sizeMeters: 20)
        let center = sectorEngine.centerTile(for: sector)

        XCTAssertFalse(
            engine.canClaim(
                sectorID: sectorID,
                state: .empty,
                playerTile: center,
                discoveredTileIDs: [],
                tileEngine: tileEngine
            )
        )

        let discovered = discoveredIDs(for: sector, fraction: TerritoryConstants.claimCompletionThreshold)
        XCTAssertTrue(
            engine.canClaim(
                sectorID: sectorID,
                state: .empty,
                playerTile: center,
                discoveredTileIDs: discovered,
                tileEngine: tileEngine
            )
        )

        let farTile = TileCoordinate(q: 500, r: 500)
        XCTAssertFalse(
            engine.canClaim(
                sectorID: sectorID,
                state: .empty,
                playerTile: farTile,
                discoveredTileIDs: discovered,
                tileEngine: tileEngine
            )
        )
    }

    func testClaimSetsFirstHomeBase() {
        let sector = SectorCoordinate(q: 1, r: 0)
        let sectorID = sectorEngine.sectorID(for: sector, sizeMeters: 20)
        let center = sectorEngine.centerTile(for: sector)
        let discovered = discoveredIDs(for: sector, fraction: 0.3)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let next = engine.claimSector(
            sectorID: sectorID,
            state: .empty,
            playerTile: center,
            discoveredTileIDs: discovered,
            tileEngine: tileEngine,
            at: date
        )

        XCTAssertEqual(next?.homeSectorID, sectorID)
        XCTAssertEqual(next?.claims.count, 1)
        XCTAssertEqual(next?.homeMovedAt, date)
        XCTAssertTrue(next?.isClaimed(sectorID) == true)
    }

    func testHomeMoveRespectsCooldown() {
        let first = SectorCoordinate(q: 0, r: 0)
        let second = SectorCoordinate(q: 1, r: 0)
        let firstID = sectorEngine.sectorID(for: first, sizeMeters: 20)
        let secondID = sectorEngine.sectorID(for: second, sizeMeters: 20)
        let claimedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = TerritoryState(
            homeSectorID: firstID,
            claims: [
                TerritoryClaim(sectorID: firstID, claimedAt: claimedAt),
                TerritoryClaim(sectorID: secondID, claimedAt: claimedAt),
            ],
            homeMovedAt: claimedAt
        )

        XCTAssertFalse(engine.canSetHomeBase(sectorID: secondID, state: state, at: claimedAt.addingTimeInterval(60)))
        XCTAssertNil(engine.setHomeBase(sectorID: secondID, state: state, at: claimedAt.addingTimeInterval(60)))

        let ready = claimedAt.addingTimeInterval(TerritoryConstants.homeMoveCooldown)
        XCTAssertTrue(engine.canSetHomeBase(sectorID: secondID, state: state, at: ready))
        state = engine.setHomeBase(sectorID: secondID, state: state, at: ready)!
        XCTAssertEqual(state.homeSectorID, secondID)
        XCTAssertEqual(state.homeMovedAt, ready)
    }

    func testFamiliarityBuffsPreferHomeBase() {
        let sector = SectorCoordinate(q: 0, r: 0)
        let sectorID = sectorEngine.sectorID(for: sector, sizeMeters: 20)
        let tile = sectorEngine.centerTile(for: sector)
        let tileID = TileEngine.makeTileID(q: tile.q, r: tile.r, sizeMeters: 20)

        let unclaimed = engine.modifiedFamiliarityXP(
            base: 20,
            tileIDs: [tileID],
            state: .empty,
            tileEngine: tileEngine
        )
        XCTAssertEqual(unclaimed, 20)

        let claimed = TerritoryState(
            homeSectorID: nil,
            claims: [TerritoryClaim(sectorID: sectorID, claimedAt: .now)],
            homeMovedAt: nil
        )
        let claimedXP = engine.modifiedFamiliarityXP(
            base: 20,
            tileIDs: [tileID],
            state: claimed,
            tileEngine: tileEngine
        )
        XCTAssertEqual(claimedXP, Int((20 * TerritoryConstants.claimFamiliarityMultiplier).rounded()))

        let home = TerritoryState(
            homeSectorID: sectorID,
            claims: [TerritoryClaim(sectorID: sectorID, claimedAt: .now)],
            homeMovedAt: .now
        )
        let homeXP = engine.modifiedFamiliarityXP(
            base: 20,
            tileIDs: [tileID],
            state: home,
            tileEngine: tileEngine
        )
        XCTAssertEqual(homeXP, Int((20 * TerritoryConstants.homeFamiliarityMultiplier).rounded()))
    }

    func testFindChanceBonusInsideClaims() {
        let sector = SectorCoordinate(q: 0, r: 0)
        let sectorID = sectorEngine.sectorID(for: sector, sizeMeters: 20)
        let tile = sectorEngine.centerTile(for: sector)
        let tileID = TileEngine.makeTileID(q: tile.q, r: tile.r, sizeMeters: 20)

        XCTAssertEqual(
            engine.findChanceBonusPercent(forTileID: tileID, state: .empty, tileEngine: tileEngine),
            0
        )

        let claimed = TerritoryState(
            homeSectorID: nil,
            claims: [TerritoryClaim(sectorID: sectorID, claimedAt: .now)],
            homeMovedAt: nil
        )
        XCTAssertEqual(
            engine.findChanceBonusPercent(forTileID: tileID, state: claimed, tileEngine: tileEngine),
            TerritoryConstants.claimFindChanceBonusPercent
        )

        let home = TerritoryState(
            homeSectorID: sectorID,
            claims: [TerritoryClaim(sectorID: sectorID, claimedAt: .now)],
            homeMovedAt: .now
        )
        XCTAssertEqual(
            engine.findChanceBonusPercent(forTileID: tileID, state: home, tileEngine: tileEngine),
            TerritoryConstants.homeFindChanceBonusPercent
        )
    }

    func testPlayerNearIncludesNeighborSectors() {
        let sector = SectorCoordinate(q: 0, r: 0)
        let sectorID = sectorEngine.sectorID(for: sector, sizeMeters: 20)
        let neighbor = sectorEngine.neighborSector(sector, directionIndex: 0)
        let neighborCenter = sectorEngine.centerTile(for: neighbor)

        XCTAssertTrue(
            engine.isPlayerNearSector(
                sectorID: sectorID,
                playerTile: neighborCenter,
                sizeMeters: 20
            )
        )
    }

    func testRollFindHonorsChanceBonus() {
        let findEngine = FieldFindEngine()
        // Pick a tile/day where the raw roll sits between base and boosted thresholds.
        // discoveryDropChancePercent = 18; with home bonus (+8) threshold = 26.
        var found: FieldFind?
        for q in 0..<200 {
            let tileID = "hex:20:\(q):0"
            let seed = StableHash.fnv1a64("find:2026-07-31:\(tileID)")
            let roll = Int(seed % 100)
            guard roll >= FieldFindConstants.discoveryDropChancePercent,
                  roll < FieldFindConstants.discoveryDropChancePercent
                    + TerritoryConstants.homeFindChanceBonusPercent else {
                continue
            }
            XCTAssertNil(
                findEngine.rollFind(
                    tileID: tileID,
                    isDiscovery: true,
                    dayKey: "2026-07-31",
                    claimedFindIDs: [],
                    findsClaimedToday: 0,
                    chanceBonusPercent: 0
                )
            )
            found = findEngine.rollFind(
                tileID: tileID,
                isDiscovery: true,
                dayKey: "2026-07-31",
                claimedFindIDs: [],
                findsClaimedToday: 0,
                chanceBonusPercent: TerritoryConstants.homeFindChanceBonusPercent
            )
            break
        }
        XCTAssertNotNil(found)
    }

    // MARK: - Helpers

    private func discoveredIDs(for sector: SectorCoordinate, fraction: Double) -> Set<String> {
        let members = Array(sectorEngine.tiles(in: sector))
        let needed = max(1, Int((Double(members.count) * fraction).rounded(.up)))
        return Set(members.prefix(needed).map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: 20)
        })
    }
}
