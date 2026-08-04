import Foundation

/// Pure skill-tree economy: points, rank-ups, diminishing modifiers.
struct SkillTreeEngine: Sendable {
    /// Absolute ceiling on AFK discoveries even with Deep Range ranked high.
    static let absoluteScoutDailyCap = 36
    /// Base combo window before Pathfinding Trail Tempo.
    static let baseFrontierComboWindow: TimeInterval = 20 * 60
    /// Soft Measure asymptotic approach rate (matches plan formula).
    static let diminishingRate = 0.15

    // MARK: - Points

    func pointsEarned(explorerLevel: Int) -> Int {
        max(0, explorerLevel - 1)
    }

    /// Cost to raise a node from `currentRank` to `currentRank + 1` is `currentRank + 1`.
    func costToRankUp(from currentRank: Int) -> Int {
        max(1, currentRank + 1)
    }

    /// Total points spent for a single node's current rank (triangular number).
    func pointsSpent(forRank rank: Int) -> Int {
        let r = max(0, rank)
        return r * (r + 1) / 2
    }

    func pointsSpent(state: SkillState) -> Int {
        state.ranks.values.reduce(0) { $0 + pointsSpent(forRank: $1) }
    }

    func pointsAvailable(explorerLevel: Int, state: SkillState) -> Int {
        max(0, pointsEarned(explorerLevel: explorerLevel) - pointsSpent(state: state))
    }

    // MARK: - Rank-up

    func canRankUp(
        nodeID: String,
        state: SkillState,
        explorerLevel: Int
    ) -> SkillRankUpResult {
        guard let node = SkillTreeCatalog.byID[nodeID] else {
            return SkillRankUpResult(outcome: .denied("Unknown skill."))
        }
        for prerequisite in node.prerequisiteIDs {
            guard state.rank(of: prerequisite) >= 1 else {
                let name = SkillTreeCatalog.byID[prerequisite]?.name ?? "a prerequisite"
                return SkillRankUpResult(outcome: .denied("Rank \(name) first."))
            }
        }
        let current = state.rank(of: nodeID)
        let cost = costToRankUp(from: current)
        let available = pointsAvailable(explorerLevel: explorerLevel, state: state)
        guard available >= cost else {
            return SkillRankUpResult(outcome: .denied("Need \(cost) skill point\(cost == 1 ? "" : "s")."))
        }
        return SkillRankUpResult(outcome: .ranked(nodeID: nodeID, newRank: current + 1, cost: cost))
    }

    @discardableResult
    func applyRankUp(
        nodeID: String,
        state: inout SkillState,
        explorerLevel: Int
    ) -> SkillRankUpResult {
        let result = canRankUp(nodeID: nodeID, state: state, explorerLevel: explorerLevel)
        guard case .ranked(_, let newRank, _) = result.outcome else { return result }
        state.ranks[nodeID] = newRank
        return result
    }

    // MARK: - Modifiers

    /// Asymptotic bonus: `peak * (1 - 1/(1 + rate * rank))`.
    func diminishingBonus(peak: Double, rank: Int, rate: Double = diminishingRate) -> Double {
        guard rank > 0, peak > 0 else { return 0 }
        return peak * (1 - 1 / (1 + rate * Double(rank)))
    }

    func modifiers(for state: SkillState) -> SkillModifiers {
        var mods = SkillModifiers.identity
        for node in SkillTreeCatalog.all {
            let rank = state.rank(of: node.id)
            guard rank > 0 else { continue }
            let bonus = diminishingBonus(peak: node.peakBonus, rank: rank)
            apply(effect: node.effectKind, bonus: bonus, peak: node.peakBonus, rank: rank, into: &mods)
        }
        mods.scoutDailyCapBonus = min(
            mods.scoutDailyCapBonus,
            Self.absoluteScoutDailyCap - IdleConstants.dailyScoutDiscoveryCap
        )
        mods.masteryThresholdMultiplier = max(0.75, mods.masteryThresholdMultiplier)
        mods.insightCostMultiplier = max(0.50, mods.insightCostMultiplier)
        return mods
    }

    func snapshot(explorerLevel: Int, state: SkillState) -> SkillTreeSnapshot {
        let spent = pointsSpent(state: state)
        let earned = pointsEarned(explorerLevel: explorerLevel)
        return SkillTreeSnapshot(
            explorerLevel: explorerLevel,
            pointsEarned: earned,
            pointsSpent: spent,
            pointsAvailable: max(0, earned - spent),
            ranks: state.ranks,
            modifiers: modifiers(for: state)
        )
    }

    /// Human-readable bonus line for a node at its current rank (next rank preview when rank==0 uses rank 1).
    func bonusDescription(for node: SkillNodeDefinition, rank: Int) -> String {
        let effectiveRank = max(rank, 0)
        let bonus = diminishingBonus(peak: node.peakBonus, rank: max(effectiveRank, 1))
        switch node.effectKind {
        case .discoveryXP:
            return String(format: "+%.0f%% discovery XP", bonus * 100)
        case .familiarityXP:
            return String(format: "+%.0f%% familiarity XP", bonus * 100)
        case .masteryThreshold:
            return String(format: "−%.0f%% mastery thresholds", bonus * 100)
        case .masteryPulse:
            return String(format: "+%.0f%% survey pulse XP", bonus * 100)
        case .scoutThroughput:
            return String(format: "+%.0f%% scout tiles/h", bonus * 100)
        case .scoutDailyCap:
            let capBonus = Int((Double(IdleConstants.dailyScoutDiscoveryCap) * bonus).rounded())
            return "+\(capBonus) daily AFK discoveries"
        case .frontierCombo:
            let seconds = Int((Self.baseFrontierComboWindow * bonus).rounded())
            let minutes = seconds / 60
            return "+\(minutes)m frontier combo"
        case .findChance:
            return String(format: "+%.0f find chance", bonus * 20)
        case .findQuality:
            return String(format: "+%.0f rare spark chance", bonus * 15)
        case .claimBuff:
            return String(format: "+%.0f%% claim buff strength", bonus * 100)
        case .factorySpeed:
            return String(format: "+%.0f%% factory speed", bonus * 100)
        case .insightCost:
            return String(format: "−%.0f%% Insight research cost", bonus * 100)
        }
    }

    // MARK: - Private

    private func apply(
        effect: SkillEffectKind,
        bonus: Double,
        peak: Double,
        rank: Int,
        into mods: inout SkillModifiers
    ) {
        switch effect {
        case .discoveryXP:
            mods.discoveryXPMultiplier += bonus
        case .familiarityXP:
            mods.familiarityXPMultiplier += bonus
        case .masteryThreshold:
            mods.masteryThresholdMultiplier -= bonus
        case .masteryPulse:
            mods.masteryPulseMultiplier += bonus
        case .scoutThroughput:
            mods.scoutThroughputMultiplier += bonus
        case .scoutDailyCap:
            let added = Int((Double(IdleConstants.dailyScoutDiscoveryCap) * bonus).rounded())
            mods.scoutDailyCapBonus += max(0, added)
        case .frontierCombo:
            mods.frontierComboWindowBonus += Self.baseFrontierComboWindow * bonus
        case .findChance:
            mods.findChanceBonusPercent += Int((bonus * 20).rounded())
        case .findQuality:
            mods.findQualityBonusPercent += Int((bonus * 15).rounded())
        case .claimBuff:
            mods.claimBuffMultiplier += bonus
        case .factorySpeed:
            mods.factorySpeedMultiplier += bonus
        case .insightCost:
            mods.insightCostMultiplier -= bonus
        }
    }
}
