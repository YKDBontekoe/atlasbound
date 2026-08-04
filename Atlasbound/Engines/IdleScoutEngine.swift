import Foundation

/// Pure idle-pack logic: scout hire/unlock chain, Home drip, capped AFK discovery picks.
struct IdleScoutEngine: Sendable {
    private let sectorEngine = HexSectorEngine()

    // MARK: - Hire / unlock

    func canHire(
        scoutID: String,
        state: IdleState,
        explorerLevel: Int,
        availableQuantity: (String) -> Int
    ) -> ScoutHireResult {
        guard let definition = ScoutCatalog.byID[scoutID] else {
            return .denied("Unknown scout.")
        }
        guard state.isUnlocked(scoutID) else {
            return .denied("\(definition.name) is still locked.")
        }
        guard !state.isHired(scoutID) else {
            return .denied("\(definition.name) is already on the roster.")
        }
        if let prerequisite = definition.prerequisiteScoutID, !state.isHired(prerequisite) {
            let name = ScoutCatalog.byID[prerequisite]?.name ?? "the previous scout"
            return .denied("Hire \(name) first.")
        }
        guard explorerLevel >= definition.explorerLevel else {
            return .denied("Requires Explorer level \(definition.explorerLevel).")
        }
        for cost in definition.hireCost where availableQuantity(cost.itemID) < cost.quantity {
            let name = ItemCatalog.definition(for: cost.itemID)?.name ?? cost.itemID
            return .denied("Need \(cost.quantity)× \(name).")
        }
        return .hired(definition)
    }

    /// Applies a hire after the caller has validated costs and consumed materials.
    func applyHire(
        definition: ScoutDefinition,
        state: inout IdleState,
        at date: Date = .now
    ) {
        guard !state.isHired(definition.id) else { return }
        state.hiredScouts.append(HiredScout(definitionID: definition.id, hiredAt: date))
        if let unlocks = definition.unlocksScoutID {
            state.unlockedScoutIDs.insert(unlocks)
        }
    }

    // MARK: - Offline advance

    /// Advances home drip accumulators and selects capped fogged tile IDs for scouts.
    /// Does not mutate the atlas — caller applies `report.scoutTileIDs` via visit processing.
    func advance(
        state: inout IdleState,
        to date: Date,
        territory: TerritoryState,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine,
        calendar: Calendar = .current,
        modifiers: SkillModifiers = .identity
    ) -> IdleAdvanceReport {
        let elapsed = max(0, Int(date.timeIntervalSince(state.lastSimulatedAt) / 60))
        let minutes = min(elapsed, IdleConstants.maximumOfflineMinutes)
        guard minutes > 0 else {
            return IdleAdvanceReport(
                simulatedMinutes: 0,
                homeDripItems: [],
                scoutTileIDs: [],
                scoutDiscoveriesGranted: 0,
                at: date
            )
        }

        rollDiscoveryDayIfNeeded(state: &state, at: date, calendar: calendar)

        let drip = homeDrip(forMinutes: minutes, hasHomeBase: territory.hasHomeBase, state: &state)
        let tileIDs = scoutDiscoveries(
            forMinutes: minutes,
            state: &state,
            territory: territory,
            discoveredTileIDs: discoveredTileIDs,
            tileEngine: tileEngine,
            dayKey: state.scoutDiscoveryDayKey ?? dayKey(for: date, calendar: calendar),
            modifiers: modifiers
        )

        // Cap catch-up, then stamp now so the next open does not re-apply the same window.
        state.lastSimulatedAt = date

        let report = IdleAdvanceReport(
            simulatedMinutes: minutes,
            homeDripItems: drip,
            scoutTileIDs: tileIDs,
            scoutDiscoveriesGranted: tileIDs.count,
            at: date
        )
        state.lastReport = report
        state.scoutDiscoveriesToday += tileIDs.count
        return report
    }

    // MARK: - Circuit reward

    func canClaimCircuitReward(
        snapshot: DailyChallengeSnapshot,
        state: IdleState
    ) -> CircuitRewardClaimResult {
        guard snapshot.isComplete else {
            return .denied("Finish today’s Scout Circuit first.")
        }
        guard state.claimedCircuitRewardDayKey != snapshot.dayKey else {
            return .denied("Circuit chest already claimed today.")
        }
        return .claimed(IdleConstants.circuitReward)
    }

    func claimCircuitReward(
        snapshot: DailyChallengeSnapshot,
        state: inout IdleState
    ) -> CircuitRewardClaimResult {
        let result = canClaimCircuitReward(snapshot: snapshot, state: state)
        guard case .claimed(let rewards) = result else { return result }
        state.claimedCircuitRewardDayKey = snapshot.dayKey
        return .claimed(rewards)
    }

    // MARK: - Home drip

    func homeDrip(
        forMinutes minutes: Int,
        hasHomeBase: Bool,
        state: inout IdleState
    ) -> [ItemAmount] {
        guard hasHomeBase, minutes > 0 else { return [] }
        let total = state.homeDripIntervalAccumulator + minutes
        let intervals = total / IdleConstants.homeDripIntervalMinutes
        state.homeDripIntervalAccumulator = total % IdleConstants.homeDripIntervalMinutes
        guard intervals > 0 else { return [] }

        var merged: [String: Int] = [:]
        for _ in 0..<intervals {
            for amount in IdleConstants.homeDripPerInterval {
                merged[amount.itemID, default: 0] += amount.quantity
            }
        }
        let completedBefore = state.homeDripIntervalsCompleted
        let completedAfter = completedBefore + intervals
        let bonusIntervals =
            (completedAfter / IdleConstants.homeDripBonusEveryIntervals)
            - (completedBefore / IdleConstants.homeDripBonusEveryIntervals)
        state.homeDripIntervalsCompleted = completedAfter
        for _ in 0..<bonusIntervals {
            for amount in IdleConstants.homeDripBonus {
                merged[amount.itemID, default: 0] += amount.quantity
            }
        }
        return merged
            .map { ItemAmount(itemID: $0.key, quantity: $0.value) }
            .sorted { $0.itemID < $1.itemID }
    }

    // MARK: - Scout tile picks

    func scoutDiscoveries(
        forMinutes minutes: Int,
        state: inout IdleState,
        territory: TerritoryState,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine,
        dayKey: String,
        modifiers: SkillModifiers = .identity
    ) -> [String] {
        guard minutes > 0, !state.hiredScouts.isEmpty, territory.hasHomeBase else { return [] }
        let dailyCap = min(
            SkillTreeEngine.absoluteScoutDailyCap,
            IdleConstants.dailyScoutDiscoveryCap + max(0, modifiers.scoutDailyCapBonus)
        )
        let remaining = max(0, dailyCap - state.scoutDiscoveriesToday)
        guard remaining > 0 else { return [] }

        let rate = Double(state.totalTilesPerHour) * max(1, modifiers.scoutThroughputMultiplier)
        guard rate > 0 else { return [] }
        state.scoutDiscoveryAccumulator += rate * Double(minutes) / 60.0
        let wanted = min(Int(state.scoutDiscoveryAccumulator), remaining)
        guard wanted > 0 else { return [] }

        let candidates = foggedCandidates(
            territory: territory,
            discoveredTileIDs: discoveredTileIDs,
            tileEngine: tileEngine,
            dayKey: dayKey
        )
        let picked = Array(candidates.prefix(wanted))
        state.scoutDiscoveryAccumulator -= Double(picked.count)
        if state.scoutDiscoveryAccumulator < 0 {
            state.scoutDiscoveryAccumulator = 0
        }
        return picked
    }

    /// Deterministic fogged tile IDs inside claimed sectors (Home first), never persisted geometry.
    func foggedCandidates(
        territory: TerritoryState,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine,
        dayKey: String
    ) -> [String] {
        var orderedSectors: [String] = []
        if let home = territory.homeSectorID {
            orderedSectors.append(home)
        }
        for claim in territory.claims where claim.sectorID != territory.homeSectorID {
            orderedSectors.append(claim.sectorID)
        }

        var homePicks: [String] = []
        var claimPicks: [String] = []
        var seen = Set<String>()

        for sectorID in orderedSectors {
            guard let parsed = sectorEngine.parseSectorID(sectorID) else { continue }
            let center = sectorEngine.centerTile(for: parsed.sector)
            for tile in tileEngine.ring(around: center, radius: IdleConstants.scoutSearchRadius) {
                guard sectorEngine.sectorID(for: tile, sizeMeters: tileEngine.tileSizeMeters) == sectorID
                else { continue }
                let id = TileEngine.makeTileID(
                    q: tile.q,
                    r: tile.r,
                    sizeMeters: tileEngine.tileSizeMeters
                )
                guard !discoveredTileIDs.contains(id), seen.insert(id).inserted else { continue }
                if sectorID == territory.homeSectorID {
                    homePicks.append(id)
                } else {
                    claimPicks.append(id)
                }
            }
        }

        let sortedHome = homePicks.sorted {
            StableHash.fnv1a64("idle-scout:\(dayKey):\($0)") < StableHash.fnv1a64("idle-scout:\(dayKey):\($1)")
        }
        let sortedClaims = claimPicks.sorted {
            StableHash.fnv1a64("idle-scout:\(dayKey):\($0)") < StableHash.fnv1a64("idle-scout:\(dayKey):\($1)")
        }
        return sortedHome + sortedClaims
    }

    // MARK: - Day keys

    func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func rollDiscoveryDayIfNeeded(
        state: inout IdleState,
        at date: Date,
        calendar: Calendar
    ) {
        let key = dayKey(for: date, calendar: calendar)
        if state.scoutDiscoveryDayKey != key {
            state.scoutDiscoveryDayKey = key
            state.scoutDiscoveriesToday = 0
        }
    }
}
