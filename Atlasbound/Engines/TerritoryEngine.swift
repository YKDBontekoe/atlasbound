import Foundation

/// Pure claim eligibility, Home Base rules, and soft territory buffs.
struct TerritoryEngine: Sendable {
    private let sectorEngine = HexSectorEngine()

    // MARK: - Sector helpers

    func sectorID(for tile: TileCoordinate, sizeMeters: Double) -> String {
        sectorEngine.sectorID(for: tile, sizeMeters: sizeMeters)
    }

    func parseSectorID(_ id: String) -> SectorCoordinate? {
        sectorEngine.parseSectorID(id)?.sector
    }

    func displayName(forSectorID sectorID: String) -> String {
        guard let sector = parseSectorID(sectorID) else { return "Unknown sector" }
        return sectorEngine.displayName(for: sector)
    }

    func completionFraction(
        sectorID: String,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine
    ) -> Double {
        guard let sector = parseSectorID(sectorID) else { return 0 }
        return sectorEngine.completionFraction(
            sector: sector,
            discoveredTileIDs: discoveredTileIDs,
            tileEngine: tileEngine
        )
    }

    /// Player is inside the sector or in any of its six neighbor sectors.
    func isPlayerNearSector(
        sectorID: String,
        playerTile: TileCoordinate?,
        sizeMeters: Double
    ) -> Bool {
        guard let playerTile,
              let target = parseSectorID(sectorID) else {
            return false
        }
        let playerSector = sectorEngine.sectorCoordinate(for: playerTile)
        if playerSector == target { return true }
        for direction in 0..<6 {
            if sectorEngine.neighborSector(target, directionIndex: direction) == playerSector {
                return true
            }
        }
        // Also accept when the target is a neighbor of the player's sector (symmetric).
        _ = sizeMeters
        return false
    }

    func boundaryTileIDs(forSectorID sectorID: String, sizeMeters: Double) -> Set<String> {
        guard let sector = parseSectorID(sectorID) else { return [] }
        return Set(sectorEngine.boundaryTiles(for: sector).map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: sizeMeters)
        })
    }

    func centerCoordinate(
        forSectorID sectorID: String,
        tileEngine: TileEngine
    ) -> (q: Int, r: Int)? {
        guard let sector = parseSectorID(sectorID) else { return nil }
        let center = sectorEngine.centerTile(for: sector)
        return (center.q, center.r)
    }

    // MARK: - Eligibility

    func canClaim(
        sectorID: String,
        state: TerritoryState,
        playerTile: TileCoordinate?,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine
    ) -> Bool {
        guard !state.isClaimed(sectorID) else { return false }
        guard isPlayerNearSector(
            sectorID: sectorID,
            playerTile: playerTile,
            sizeMeters: tileEngine.tileSizeMeters
        ) else {
            return false
        }
        let fraction = completionFraction(
            sectorID: sectorID,
            discoveredTileIDs: discoveredTileIDs,
            tileEngine: tileEngine
        )
        return fraction + 0.000_1 >= TerritoryConstants.claimCompletionThreshold
    }

    func canSetHomeBase(
        sectorID: String,
        state: TerritoryState,
        at date: Date = .now
    ) -> Bool {
        guard state.isClaimed(sectorID) else { return false }
        if state.homeSectorID == sectorID { return false }
        if state.homeSectorID == nil { return true }
        guard let movedAt = state.homeMovedAt else { return true }
        return date.timeIntervalSince(movedAt) >= TerritoryConstants.homeMoveCooldown
    }

    func homeMoveReadyAt(state: TerritoryState) -> Date? {
        guard state.homeSectorID != nil, let movedAt = state.homeMovedAt else { return nil }
        return movedAt.addingTimeInterval(TerritoryConstants.homeMoveCooldown)
    }

    // MARK: - Mutations

    func claimSector(
        sectorID: String,
        state: TerritoryState,
        playerTile: TileCoordinate?,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine,
        at date: Date = .now
    ) -> TerritoryState? {
        guard canClaim(
            sectorID: sectorID,
            state: state,
            playerTile: playerTile,
            discoveredTileIDs: discoveredTileIDs,
            tileEngine: tileEngine
        ) else {
            return nil
        }
        var next = state
        next.claims.append(TerritoryClaim(sectorID: sectorID, claimedAt: date))
        next.claims.sort { $0.sectorID < $1.sectorID }
        if next.homeSectorID == nil {
            next.homeSectorID = sectorID
            next.homeMovedAt = date
        }
        return next
    }

    func setHomeBase(
        sectorID: String,
        state: TerritoryState,
        at date: Date = .now
    ) -> TerritoryState? {
        guard canSetHomeBase(sectorID: sectorID, state: state, at: date) else { return nil }
        var next = state
        next.homeSectorID = sectorID
        next.homeMovedAt = date
        return next
    }

    // MARK: - Buffs

    func familiarityMultiplier(
        forSectorID sectorID: String?,
        state: TerritoryState,
        claimBuffMultiplier: Double = 1
    ) -> Double {
        guard let sectorID, state.isClaimed(sectorID) else { return 1 }
        let base: Double
        if state.homeSectorID == sectorID {
            base = TerritoryConstants.homeFamiliarityMultiplier
        } else {
            base = TerritoryConstants.claimFamiliarityMultiplier
        }
        // Amplify only the buff portion above 1.0.
        let buff = (base - 1) * max(1, claimBuffMultiplier)
        return 1 + buff
    }

    func findChanceBonusPercent(
        forSectorID sectorID: String?,
        state: TerritoryState,
        claimBuffMultiplier: Double = 1
    ) -> Int {
        guard let sectorID, state.isClaimed(sectorID) else { return 0 }
        let base: Int
        if state.homeSectorID == sectorID {
            base = TerritoryConstants.homeFindChanceBonusPercent
        } else {
            base = TerritoryConstants.claimFindChanceBonusPercent
        }
        return Int((Double(base) * max(1, claimBuffMultiplier)).rounded())
    }

    /// Average familiarity multiplier across visited tiles (unclaimed = 1.0).
    func modifiedFamiliarityXP(
        base: Int,
        tileIDs: [String],
        state: TerritoryState,
        tileEngine: TileEngine,
        claimBuffMultiplier: Double = 1
    ) -> Int {
        guard base > 0, !tileIDs.isEmpty else { return base }
        var total = 0.0
        var count = 0
        for tileID in tileIDs {
            guard let axial = tileEngine.parseTileID(tileID) else { continue }
            let sectorID = sectorEngine.sectorID(for: axial, sizeMeters: tileEngine.tileSizeMeters)
            total += familiarityMultiplier(
                forSectorID: sectorID,
                state: state,
                claimBuffMultiplier: claimBuffMultiplier
            )
            count += 1
        }
        guard count > 0 else { return base }
        let average = total / Double(count)
        return max(base, Int((Double(base) * average).rounded()))
    }

    func findChanceBonusPercent(
        forTileID tileID: String,
        state: TerritoryState,
        tileEngine: TileEngine,
        claimBuffMultiplier: Double = 1
    ) -> Int {
        guard let axial = tileEngine.parseTileID(tileID) else { return 0 }
        let sectorID = sectorEngine.sectorID(for: axial, sizeMeters: tileEngine.tileSizeMeters)
        return findChanceBonusPercent(
            forSectorID: sectorID,
            state: state,
            claimBuffMultiplier: claimBuffMultiplier
        )
    }

    // MARK: - Presence

    func presenceSnapshot(
        playerTile: TileCoordinate?,
        state: TerritoryState,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine,
        at date: Date = .now
    ) -> TerritoryPresenceSnapshot {
        guard let playerTile else {
            var empty = TerritoryPresenceSnapshot.empty
            empty.claimCount = state.claimCount
            empty.homeMoveReadyAt = homeMoveReadyAt(state: state)
            return empty
        }
        let sector = sectorEngine.sectorCoordinate(for: playerTile)
        let sectorID = sectorEngine.sectorID(for: sector, sizeMeters: tileEngine.tileSizeMeters)
        let fraction = sectorEngine.completionFraction(
            sector: sector,
            discoveredTileIDs: discoveredTileIDs,
            tileEngine: tileEngine
        )
        let claimed = state.isClaimed(sectorID)
        return TerritoryPresenceSnapshot(
            playerSectorID: sectorID,
            playerSectorName: sectorEngine.displayName(for: sector),
            completionFraction: fraction,
            isClaimed: claimed,
            isHomeBase: state.homeSectorID == sectorID,
            canClaim: canClaim(
                sectorID: sectorID,
                state: state,
                playerTile: playerTile,
                discoveredTileIDs: discoveredTileIDs,
                tileEngine: tileEngine
            ),
            canSetHome: canSetHomeBase(sectorID: sectorID, state: state, at: date),
            homeMoveReadyAt: homeMoveReadyAt(state: state),
            claimCount: state.claimCount
        )
    }

    /// Boundary tiles for all claimed sectors (map wash). Caps sampling cost via sector set.
    func claimedBoundaryTileIDs(state: TerritoryState, sizeMeters: Double) -> Set<String> {
        var ids: Set<String> = []
        for claim in state.claims {
            ids.formUnion(boundaryTileIDs(forSectorID: claim.sectorID, sizeMeters: sizeMeters))
        }
        return ids
    }
}
