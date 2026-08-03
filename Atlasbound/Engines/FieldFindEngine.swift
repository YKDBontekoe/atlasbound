import Foundation

/// Deterministic field-find rolls, loot tables, craft/salvage, and effect blueprints.
struct FieldFindEngine: Sendable {
    func localDayKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    func findID(dayKey: String, tileID: String) -> String {
        "find:\(dayKey):\(tileID)"
    }

    /// Rolls a find for a visited tile. Same day+tile+distance band is deterministic.
    func rollFind(
        tileID: String,
        isDiscovery: Bool,
        dayKey: String,
        claimedFindIDs: Set<String>,
        findsClaimedToday: Int,
        chanceBonusPercent: Int = 0,
        metersFromHome: Double? = nil
    ) -> FieldFind? {
        guard findsClaimedToday < FieldFindConstants.maxFindsPerDay else { return nil }
        let id = findID(dayKey: dayKey, tileID: tileID)
        guard !claimedFindIDs.contains(id) else { return nil }

        let seed = StableHash.fnv1a64("find:\(dayKey):\(tileID)")
        let chanceRoll = Int(seed % 100)
        let baseThreshold = isDiscovery
            ? FieldFindConstants.discoveryDropChancePercent
            : FieldFindConstants.revisitDropChancePercent
        let threshold = min(100, baseThreshold + max(0, chanceBonusPercent))
        guard chanceRoll < threshold else { return nil }

        let band = DistanceLootEngine.band(meters: metersFromHome ?? 0)
        let itemID = pickItemID(seed: seed, isDiscovery: isDiscovery, band: band)
        let quantity = 1 + Int((seed / 97) % 2) // 1 or 2 for materials-heavy rolls feel
        let qty = ItemCatalog.definition(for: itemID)?.category == .material ? quantity : 1

        return FieldFind(
            id: id,
            tileID: tileID,
            dayKey: dayKey,
            itemID: itemID,
            quantity: qty,
            isDiscoveryDrop: isDiscovery
        )
    }

    /// Nearby tiles that would yield a find today (preview only; does not claim).
    func previewFinds(
        around anchor: TileCoordinate,
        radius: Int,
        tileEngine: TileEngine,
        dayKey: String,
        claimedFindIDs: Set<String>,
        isTileDiscovered: (String) -> Bool,
        homeCenter: TileCoordinate? = nil
    ) -> [FieldFindPreview] {
        let ring = tileEngine.ring(around: anchor, radius: radius)
        var previews: [FieldFindPreview] = []
        for axial in ring {
            let tileID = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: tileEngine.tileSizeMeters)
            let id = findID(dayKey: dayKey, tileID: tileID)
            guard !claimedFindIDs.contains(id) else { continue }
            let discovered = isTileDiscovered(tileID)
            let metersFromHome: Double? = homeCenter.map { home in
                DistanceLootEngine.meters(
                    hexDistance: TileEngine.hexDistance(home, axial),
                    tileSizeMeters: tileEngine.tileSizeMeters
                )
            }
            // Previews prefer undiscovered edges; include light revisit chance tiles too.
            guard let find = rollFind(
                tileID: tileID,
                isDiscovery: !discovered,
                dayKey: dayKey,
                claimedFindIDs: claimedFindIDs,
                findsClaimedToday: 0,
                metersFromHome: metersFromHome
            ) else { continue }
            let rarity = ItemCatalog.definition(for: find.itemID)?.rarity ?? .common
            previews.append(FieldFindPreview(id: find.id, tileID: tileID, itemID: find.itemID, rarity: rarity))
            if previews.count >= FieldFindConstants.maxMapPreviews { break }
        }
        return previews
    }

    func canAssemble(recipe: RecipeDefinition, stacks: [InventoryStack]) -> Bool {
        let quantities = Dictionary(uniqueKeysWithValues: stacks.map { ($0.itemID, $0.quantity) })
        for input in recipe.inputs {
            guard (quantities[input.itemID] ?? 0) >= input.quantity else { return false }
        }
        return true
    }

    func salvageYield(for itemID: String, seed: UInt64? = nil) -> [(itemID: String, quantity: Int)] {
        guard let def = ItemCatalog.definition(for: itemID), def.canSalvage, def.rarity >= .uncommon else {
            return []
        }
        let value = seed ?? StableHash.fnv1a64("salvage:\(itemID)")
        let materials = ItemCatalog.materials
        let first = materials[Int(value % UInt64(materials.count))]
        var yields = [(first.id, 1)]
        if def.rarity >= .rare {
            let second = materials[Int((value / 11) % UInt64(materials.count))]
            if second.id != first.id {
                yields.append((second.id, 1))
            } else {
                yields[0].1 = 2
            }
        }
        return yields.map { (itemID: $0.0, quantity: $0.1) }
    }

    func makeEffect(for itemID: String, at date: Date = .now) -> ActiveItemEffect? {
        guard let def = ItemCatalog.definition(for: itemID), let kind = def.effectKind else { return nil }
        switch kind {
        case .familiarityBoost:
            let charges = itemID == "waystone_charm"
                ? FieldFindConstants.waystoneCharmCharges
                : FieldFindConstants.familiarityBoostCharges
            return ActiveItemEffect(
                id: UUID(),
                itemID: itemID,
                kind: kind,
                remainingCharges: charges,
                expiresAt: nil,
                startedAt: date
            )
        case .discoveryBonus:
            return ActiveItemEffect(
                id: UUID(),
                itemID: itemID,
                kind: kind,
                remainingCharges: itemID == "brass_sextant" ? 2 : 1,
                expiresAt: nil,
                startedAt: date
            )
        case .fogLantern:
            return ActiveItemEffect(
                id: UUID(),
                itemID: itemID,
                kind: kind,
                remainingCharges: 1,
                expiresAt: date.addingTimeInterval(FieldFindConstants.fogLanternDuration),
                startedAt: date
            )
        case .streakOil:
            return ActiveItemEffect(
                id: UUID(),
                itemID: itemID,
                kind: kind,
                remainingCharges: 1,
                expiresAt: nil,
                startedAt: date
            )
        case .pathbread, .surveyBeacon, .trailReroll, .vaultWhisper, .cartographerPin, .echoVial:
            return nil
        }
    }

    func modifiedFamiliarityXP(base: Int, effects: inout [ActiveItemEffect]) -> Int {
        guard base > 0 else { return base }
        guard let index = effects.firstIndex(where: { $0.kind == .familiarityBoost && $0.remainingCharges > 0 }) else {
            return base
        }
        var effect = effects[index]
        effect.remainingCharges -= 1
        if effect.remainingCharges <= 0 {
            effects.remove(at: index)
        } else {
            effects[index] = effect
        }
        return Int((Double(base) * FieldFindConstants.familiarityBoostMultiplier).rounded())
    }

    func modifiedDiscoveryXP(base: Int, effects: inout [ActiveItemEffect]) -> (xp: Int, bonus: Int) {
        guard base > 0 else { return (base, 0) }
        guard let index = effects.firstIndex(where: { $0.kind == .discoveryBonus && $0.remainingCharges > 0 }) else {
            return (base, 0)
        }
        var effect = effects[index]
        effect.remainingCharges -= 1
        let bonus = FieldFindConstants.discoveryFlareBonusXP
        if effect.remainingCharges <= 0 {
            effects.remove(at: index)
        } else {
            effects[index] = effect
        }
        return (base + bonus, bonus)
    }

    func applyStreakOilIfAvailable(
        combo: FrontierComboState,
        effects: inout [ActiveItemEffect],
        at date: Date
    ) -> FrontierComboState {
        guard let index = effects.firstIndex(where: { $0.kind == .streakOil && $0.remainingCharges > 0 }) else {
            return combo
        }
        var next = combo
        let baseExpiry = next.expiresAt ?? date
        next.expiresAt = max(baseExpiry, date).addingTimeInterval(FieldFindConstants.streakOilExtension)
        effects.remove(at: index)
        return next
    }

    func pruneExpiredEffects(_ effects: [ActiveItemEffect], at date: Date = .now) -> [ActiveItemEffect] {
        effects.filter { effect in
            if let expires = effect.expiresAt, expires <= date { return false }
            if (effect.kind == .familiarityBoost || effect.kind == .discoveryBonus),
               effect.remainingCharges <= 0 {
                return false
            }
            return true
        }
    }

    // MARK: - Private loot

    private func pickItemID(seed: UInt64, isDiscovery: Bool, band: DistanceLootBand) -> String {
        let spark = Int((seed / 13) % 100)
        let sparkChance = DistanceLootEngine.rareSparkChancePercent(for: band)
        if spark < sparkChance {
            return pickWeighted(from: rareSparkTable, seed: seed / 17)
        }
        let table = isDiscovery ? discoveryTable : revisitTable
        return pickWeighted(from: boostedTable(table, band: band), seed: seed / 17)
    }

    private func boostedTable(
        _ table: [(String, Int)],
        band: DistanceLootBand
    ) -> [(String, Int)] {
        let multiplier = DistanceLootEngine.uncommonWeightMultiplier(for: band)
        guard multiplier > 1 else { return table }
        return table.map { itemID, weight in
            let rarity = ItemCatalog.definition(for: itemID)?.rarity ?? .common
            let scaled = rarity >= .uncommon ? weight * multiplier : weight
            return (itemID, scaled)
        }
    }

    private func pickWeighted(from table: [(String, Int)], seed: UInt64) -> String {
        let total = table.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return "moss_scrap" }
        var ticket = Int(seed % UInt64(total))
        for (itemID, weight) in table {
            ticket -= weight
            if ticket < 0 { return itemID }
        }
        return table.last?.0 ?? "moss_scrap"
    }

    private var discoveryTable: [(String, Int)] {
        [
            ("moss_scrap", 18),
            ("cobble_chip", 16),
            ("trail_ribbon", 12),
            ("fog_lint", 12),
            ("waystone_shard", 8),
            ("brass_rivet", 7),
            ("survey_ink", 6),
            ("sector_dust", 6),
            ("pathbread", 5),
            ("cartographers_pin", 4),
            ("familiarity_tonic", 3),
            ("fog_lantern", 2),
            ("compass_filament", 1),
            ("river_pebble", 8),
            ("amber_resin", 4),
            ("copper_wire", 3),
        ]
    }

    private var revisitTable: [(String, Int)] {
        [
            ("moss_scrap", 18),
            ("cobble_chip", 16),
            ("fog_lint", 12),
            ("trail_ribbon", 10),
            ("river_pebble", 10),
            ("pathbread", 8),
            ("sector_dust", 6),
            ("amber_resin", 5),
            ("survey_ink", 4),
            ("vault_whisper", 4),
            ("familiarity_tonic", 3),
            ("discovery_flare", 3),
            ("copper_wire", 3),
            ("brass_rivet", 2),
            ("echo_vial", 1),
            ("streak_oil", 1),
        ]
    }

    private var rareSparkTable: [(String, Int)] {
        [
            ("compass_filament", 22),
            ("landmark_fibers", 18),
            ("discovery_flare", 14),
            ("streak_oil", 12),
            ("survey_beacon", 10),
            ("trail_reroll_token", 10),
            ("echo_vial", 8),
            ("fog_lantern", 6),
        ]
    }
}
