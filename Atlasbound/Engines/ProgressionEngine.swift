import Foundation

/// Awards discovery XP on first visit; familiarity/mastery XP on revisits (diminishing).
struct ProgressionEngine: Sendable {
    static let discoveryXP: Int = 100

    /// Base familiarity XP before diminishing returns.
    static let baseFamiliarityXP: Int = 25
    static let familiarityXPFloor: Int = 5
    /// Diminishing revisit awards after discovery (index 0 = first revisit).
    static let familiarityXPTable: [Int] = [baseFamiliarityXP, 20, 16, 12, 10]

    static let exploredMasteryXP: Int = 150
    static let surveyedMasteryXP: Int = 200
    static let masteredMasteryXP: Int = 300
    static let legendaryMasteryXP: Int = 500

    func processVisit(
        tile: inout WorldTile,
        at date: Date = .now,
        activity: ActivityType = .unknown
    ) -> VisitResult {
        tile.activityStamps.insert(activity)

        if tile.state == .fogged || tile.firstVisitedAt == nil {
            return applyDiscovery(&tile, at: date)
        } else {
            return applyFamiliarity(&tile, at: date)
        }
    }

    func processVisits(
        tileIDs: [String],
        tiles: inout [String: WorldTile],
        tileEngine: TileEngine,
        at date: Date = .now,
        activity: ActivityType = .unknown
    ) -> SessionProgress {
        var discoveryXP = 0
        var familiarityXP = 0
        var discovered = 0
        var revisited = 0

        for id in tileIDs {
            var tile = tiles[id] ?? makeTile(id: id, engine: tileEngine)
            let result = processVisit(tile: &tile, at: date, activity: activity)
            tiles[id] = tile

            switch result.kind {
            case .discovery:
                discovered += 1
                discoveryXP += result.xpAwarded
            case .familiarity:
                revisited += 1
                familiarityXP += result.xpAwarded
            }
        }

        return SessionProgress(
            tilesVisited: tileIDs.count,
            tilesDiscovered: discovered,
            tilesRevisited: revisited,
            discoveryXP: discoveryXP,
            familiarityXP: familiarityXP
        )
    }

    // MARK: - Private

    private func applyDiscovery(_ tile: inout WorldTile, at date: Date) -> VisitResult {
        tile.state = .discovered
        tile.masteryXP += Self.discoveryXP
        tile.visitCount = max(tile.visitCount, 0) + 1
        tile.firstVisitedAt = date
        tile.lastVisitedAt = date
        tile.uniqueVisitDays = 1
        return VisitResult(kind: .discovery, xpAwarded: Self.discoveryXP, tileID: tile.id)
    }

    private func applyFamiliarity(_ tile: inout WorldTile, at date: Date) -> VisitResult {
        let xp = familiarityXP(forVisitCount: tile.visitCount)
        tile.masteryXP += xp
        tile.visitCount += 1

        let calendar = Calendar.current
        if let previous = tile.lastVisitedAt, !calendar.isDate(previous, inSameDayAs: date) {
            tile.uniqueVisitDays += 1
        }
        tile.lastVisitedAt = date

        advanceStateIfNeeded(&tile)

        return VisitResult(kind: .familiarity, xpAwarded: xp, tileID: tile.id)
    }

    /// Diminishing familiarity from `familiarityXPTable`, then `familiarityXPFloor`.
    /// `existingVisits` is the visit count before this revisit (at least 1 after discovery).
    func familiarityXP(forVisitCount existingVisits: Int) -> Int {
        let revisitIndex = max(existingVisits, 1)
        let table = Self.familiarityXPTable
        if revisitIndex - 1 < table.count {
            return table[revisitIndex - 1]
        }
        return Self.familiarityXPFloor
    }

    private func advanceStateIfNeeded(_ tile: inout WorldTile) {
        // Lightweight thresholds — skill tree can layer on top.
        switch tile.masteryXP {
        case Self.legendaryMasteryXP...:
            if tile.state.rawValue < TileState.legendary.rawValue { tile.state = .legendary }
        case Self.masteredMasteryXP..<Self.legendaryMasteryXP:
            if tile.state.rawValue < TileState.mastered.rawValue { tile.state = .mastered }
        case Self.surveyedMasteryXP..<Self.masteredMasteryXP:
            if tile.state.rawValue < TileState.surveyed.rawValue { tile.state = .surveyed }
        case Self.exploredMasteryXP..<Self.surveyedMasteryXP:
            if tile.state.rawValue < TileState.explored.rawValue { tile.state = .explored }
        default:
            break
        }
    }

    private func makeTile(id: String, engine: TileEngine) -> WorldTile {
        let coordinate = engine.parseTileID(id) ?? TileCoordinate(q: 0, r: 0)
        return WorldTile(id: id, coordinate: coordinate)
    }
}

enum VisitKind: Sendable {
    case discovery
    case familiarity
}

struct VisitResult: Sendable {
    let kind: VisitKind
    let xpAwarded: Int
    let tileID: String
}

struct SessionProgress: Sendable {
    var tilesVisited: Int
    var tilesDiscovered: Int
    var tilesRevisited: Int
    var discoveryXP: Int
    var familiarityXP: Int

    static let empty = SessionProgress(
        tilesVisited: 0,
        tilesDiscovered: 0,
        tilesRevisited: 0,
        discoveryXP: 0,
        familiarityXP: 0
    )
}
