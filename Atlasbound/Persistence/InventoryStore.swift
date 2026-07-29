import Foundation
import Combine

private struct InventorySaveFile: Codable {
    var version: Int
    var stacks: [InventoryStack]
    var claimedFindIDs: [String]
    var claimedFindDayKey: String
    var findsClaimedToday: Int
    var activeEffects: [ActiveItemEffect]
    var cartographerPins: [CartographerPin]
    var lifetimeFindsCollected: Int
}

@MainActor
final class InventoryStore: ObservableObject {
    @Published private(set) var stacks: [InventoryStack] = []
    @Published private(set) var activeEffects: [ActiveItemEffect] = []
    @Published private(set) var cartographerPins: [CartographerPin] = []
    @Published private(set) var findsClaimedToday = 0
    @Published private(set) var lifetimeFindsCollected = 0
    @Published private(set) var claimedFindIDs: Set<String> = []
    @Published var latestPickup: ItemPickup?
    @Published var latestActionMessage: String?

    private let fileURL: URL
    private let engine = FieldFindEngine()
    private var claimedFindDayKey: String = ""

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? JSONFileStore.documentsURL(fileName: "atlasbound-inventory.json")
        load()
        refreshDayState()
        pruneEffects()
    }

    var sortedStacks: [InventoryStack] {
        stacks.sorted { lhs, rhs in
            let left = ItemCatalog.definition(for: lhs.itemID)
            let right = ItemCatalog.definition(for: rhs.itemID)
            let leftRarity = left?.rarity.rawValue ?? -1
            let rightRarity = right?.rarity.rawValue ?? -1
            if leftRarity != rightRarity { return leftRarity > rightRarity }
            return (left?.name ?? lhs.itemID) < (right?.name ?? rhs.itemID)
        }
    }

    var hasFogLanternActive: Bool {
        pruneEffects()
        return activeEffects.contains { $0.kind == .fogLantern }
    }

    var primaryActiveEffect: ActiveItemEffect? {
        pruneEffects()
        return activeEffects.first
    }

    // MARK: - Field finds

    /// `discoveryTileIDs` are tiles first-discovered in this visit batch.
    func processVisitedTileIDs(
        _ tileIDs: [String],
        discoveryTileIDs: Set<String>,
        date: Date = .now
    ) {
        refreshDayState(date: date)
        pruneEffects(at: date)
        guard latestPickup == nil else { return }

        for tileID in tileIDs {
            let dayKey = engine.localDayKey(for: date)
            let isDiscovery = discoveryTileIDs.contains(tileID)
            guard let find = engine.rollFind(
                tileID: tileID,
                isDiscovery: isDiscovery,
                dayKey: dayKey,
                claimedFindIDs: claimedFindIDs,
                findsClaimedToday: findsClaimedToday
            ) else { continue }
            collect(find)
            return
        }
    }

    @discardableResult
    func collect(_ find: FieldFind) -> ItemPickup? {
        guard !claimedFindIDs.contains(find.id) else { return nil }
        guard ItemCatalog.definition(for: find.itemID) != nil else { return nil }

        claimedFindIDs.insert(find.id)
        findsClaimedToday += 1
        lifetimeFindsCollected += 1
        addQuantity(find.itemID, amount: find.quantity)

        let def = ItemCatalog.definition(for: find.itemID)!
        let pickup = ItemPickup(
            id: UUID(),
            find: find,
            itemName: def.name,
            rarity: def.rarity,
            symbolName: def.symbolName
        )
        latestPickup = pickup
        trimClaimedIDsIfNeeded()
        persist()
        return pickup
    }

    func dismissPickup() {
        latestPickup = nil
    }

    func clearClaimedFindIDs() {
        claimedFindIDs = []
        findsClaimedToday = 0
        claimedFindDayKey = engine.localDayKey()
        persist()
    }

    func previewFinds(
        around anchor: TileCoordinate?,
        tileEngine: TileEngine,
        discoveredTileIDs: Set<String>,
        date: Date = .now
    ) -> [FieldFindPreview] {
        guard let anchor else { return [] }
        refreshDayState(date: date)
        return engine.previewFinds(
            around: anchor,
            radius: 5,
            tileEngine: tileEngine,
            dayKey: engine.localDayKey(for: date),
            claimedFindIDs: claimedFindIDs,
            isTileDiscovered: { discoveredTileIDs.contains($0) }
        )
    }

    // MARK: - Actions

    @discardableResult
    func useItem(itemID: String, date: Date = .now) -> ItemActionResult? {
        guard let def = ItemCatalog.definition(for: itemID),
              def.isConsumable,
              def.category == .boost || def.category == .assembled,
              quantity(of: itemID) > 0 else { return nil }

        switch def.effectKind {
        case .pathbread:
            guard consume(itemID, amount: 1) else { return nil }
            let result = ItemActionResult(
                action: .use,
                message: "Pathbread restores your stride.",
                grantedFamiliarityXP: FieldFindConstants.pathbreadFamiliarityXP,
                grantedDiscoveryXP: 0,
                outputItemID: nil,
                outputQuantity: 0
            )
            latestActionMessage = result.message
            persist()
            return result

        case .echoVial:
            guard consume(itemID, amount: 1) else { return nil }
            let result = ItemActionResult.message(.use, "Echo Vial is ready — walk a nearby tile to catch the echo.")
            // Unclaim the most recent same-day find so a nearby tile can drop again.
            if let latest = claimedFindIDs
                .filter({ $0.hasPrefix("find:\(engine.localDayKey(for: date)):") })
                .sorted()
                .last {
                claimedFindIDs.remove(latest)
                findsClaimedToday = max(0, findsClaimedToday - 1)
            }
            latestActionMessage = result.message
            persist()
            return result

        case .familiarityBoost, .discoveryBonus, .streakOil, .fogLantern:
            guard let effect = engine.makeEffect(for: itemID, at: date) else { return nil }
            guard consume(itemID, amount: 1) else { return nil }
            // Replace same-kind effect
            activeEffects.removeAll { $0.kind == effect.kind }
            activeEffects.append(effect)
            let result = ItemActionResult.message(.use, "\(def.name) activated.")
            latestActionMessage = result.message
            persist()
            return result

        case .surveyBeacon, .trailReroll, .vaultWhisper, .cartographerPin, .none:
            // Assembled items that map to charge-like effects still go through activate for those kinds.
            if def.category == .assembled, let kind = def.effectKind,
               kind == .surveyBeacon || kind == .trailReroll {
                return activateItem(itemID: itemID, date: date)
            }
            if def.category == .assembled, let effect = engine.makeEffect(for: itemID, at: date) {
                guard consume(itemID, amount: 1) else { return nil }
                activeEffects.removeAll { $0.kind == effect.kind }
                activeEffects.append(effect)
                let result = ItemActionResult.message(.use, "\(def.name) activated.")
                latestActionMessage = result.message
                persist()
                return result
            }
            return nil
        }
    }

    /// Activate charge tools. WorldController may pass context callbacks for side effects.
    @discardableResult
    func activateItem(
        itemID: String,
        date: Date = .now,
        playerTileID: String? = nil,
        vaultHint: String? = nil
    ) -> ItemActionResult? {
        guard let def = ItemCatalog.definition(for: itemID),
              def.isConsumable,
              quantity(of: itemID) > 0 else { return nil }

        let kind = def.effectKind
        switch kind {
        case .fogLantern:
            guard let effect = engine.makeEffect(for: itemID, at: date) else { return nil }
            guard consume(itemID, amount: 1) else { return nil }
            activeEffects.removeAll { $0.kind == .fogLantern }
            activeEffects.append(effect)
            let result = ItemActionResult.message(.activate, "Fog lantern lit — nearby haze widens.")
            latestActionMessage = result.message
            persist()
            return result

        case .trailReroll:
            guard consume(itemID, amount: 1) else { return nil }
            let result = ItemActionResult.message(.activate, "Trail reroll granted.")
            latestActionMessage = result.message
            persist()
            return result

        case .vaultWhisper:
            guard consume(itemID, amount: 1) else { return nil }
            let hint = vaultHint ?? "Listen for the vault when you hold three keys."
            let result = ItemActionResult.message(.activate, hint)
            latestActionMessage = result.message
            persist()
            return result

        case .cartographerPin:
            guard let playerTileID else {
                return ItemActionResult.message(.activate, "Move onto a tile before pinning.")
            }
            guard consume(itemID, amount: 1) else { return nil }
            let pin = CartographerPin(
                id: UUID(),
                tileID: playerTileID,
                note: "Pinned landmark",
                pinnedAt: date
            )
            cartographerPins.append(pin)
            if cartographerPins.count > FieldFindConstants.maxCartographerPins {
                cartographerPins = Array(cartographerPins.suffix(FieldFindConstants.maxCartographerPins))
            }
            let result = ItemActionResult.message(.activate, "Tile pinned in your journal.")
            latestActionMessage = result.message
            persist()
            return result

        case .surveyBeacon:
            guard consume(itemID, amount: 1) else { return nil }
            let result = ItemActionResult.message(.activate, "Survey beacon pulsed.")
            latestActionMessage = result.message
            persist()
            return result

        case .familiarityBoost, .discoveryBonus, .streakOil, .pathbread, .echoVial, .none:
            return useItem(itemID: itemID, date: date)
        }
    }

    @discardableResult
    func assemble(recipeID: String) -> ItemActionResult? {
        guard let recipe = ItemRecipes.recipe(id: recipeID),
              engine.canAssemble(recipe: recipe, stacks: stacks) else { return nil }
        for (itemID, needed) in recipe.inputs {
            guard consume(itemID, amount: needed) else { return nil }
        }
        addQuantity(recipe.outputItemID, amount: 1)
        let name = ItemCatalog.definition(for: recipe.outputItemID)?.name ?? recipe.displayName
        let result = ItemActionResult(
            action: .assemble,
            message: "Assembled \(name).",
            grantedFamiliarityXP: 0,
            grantedDiscoveryXP: 0,
            outputItemID: recipe.outputItemID,
            outputQuantity: 1
        )
        latestActionMessage = result.message
        persist()
        return result
    }

    @discardableResult
    func salvage(itemID: String) -> ItemActionResult? {
        let yields = engine.salvageYield(for: itemID)
        guard !yields.isEmpty, quantity(of: itemID) > 0 else { return nil }
        guard consume(itemID, amount: 1) else { return nil }
        for yield in yields {
            addQuantity(yield.itemID, amount: yield.quantity)
        }
        let names = yields.compactMap { ItemCatalog.definition(for: $0.itemID)?.name }.joined(separator: ", ")
        let result = ItemActionResult(
            action: .salvage,
            message: "Salvaged into \(names).",
            grantedFamiliarityXP: 0,
            grantedDiscoveryXP: 0,
            outputItemID: yields.first?.itemID,
            outputQuantity: yields.first?.quantity ?? 0
        )
        latestActionMessage = result.message
        persist()
        return result
    }

    @discardableResult
    func discard(itemID: String, amount: Int = 1) -> ItemActionResult? {
        guard amount > 0, consume(itemID, amount: amount) else { return nil }
        let name = ItemCatalog.definition(for: itemID)?.name ?? itemID
        let result = ItemActionResult.message(.discard, "Discarded \(name).")
        latestActionMessage = result.message
        persist()
        return result
    }

    // MARK: - Effect helpers for WorldController

    func applyXPModifiers(discovery: Int, familiarity: Int) -> (discovery: Int, familiarity: Int) {
        pruneEffects()
        var effects = activeEffects
        let familiarityOut = engine.modifiedFamiliarityXP(base: familiarity, effects: &effects)
        let discoveryOut = engine.modifiedDiscoveryXP(base: discovery, effects: &effects)
        activeEffects = effects
        if discoveryOut.bonus != 0 || familiarityOut != familiarity {
            persist()
        }
        return (discoveryOut.xp, familiarityOut)
    }

    func consumeStreakOil(combo: FrontierComboState, at date: Date = .now) -> FrontierComboState {
        pruneEffects(at: date)
        var effects = activeEffects
        let next = engine.applyStreakOilIfAvailable(combo: combo, effects: &effects, at: date)
        if effects.count != activeEffects.count {
            activeEffects = effects
            persist()
        }
        return next
    }

    func quantity(of itemID: String) -> Int {
        stacks.first { $0.itemID == itemID }?.quantity ?? 0
    }

    func craftableRecipes() -> [ItemRecipe] {
        ItemRecipes.all.filter { engine.canAssemble(recipe: $0, stacks: stacks) }
    }

    // MARK: - Private

    private func addQuantity(_ itemID: String, amount: Int) {
        guard amount > 0 else { return }
        if let index = stacks.firstIndex(where: { $0.itemID == itemID }) {
            stacks[index].quantity += amount
        } else {
            stacks.append(InventoryStack(itemID: itemID, quantity: amount))
        }
    }

    @discardableResult
    private func consume(_ itemID: String, amount: Int) -> Bool {
        guard amount > 0, let index = stacks.firstIndex(where: { $0.itemID == itemID }),
              stacks[index].quantity >= amount else { return false }
        stacks[index].quantity -= amount
        if stacks[index].quantity == 0 {
            stacks.remove(at: index)
        }
        return true
    }

    private func refreshDayState(date: Date = .now) {
        let dayKey = engine.localDayKey(for: date)
        guard claimedFindDayKey != dayKey else { return }
        claimedFindDayKey = dayKey
        findsClaimedToday = 0
        // Drop claimed IDs from other days to keep the set bounded.
        claimedFindIDs = Set(claimedFindIDs.filter { $0.hasPrefix("find:\(dayKey):") })
        persist()
    }

    private func trimClaimedIDsIfNeeded() {
        guard claimedFindIDs.count > FieldFindConstants.maxClaimedFindIDs else { return }
        let sorted = claimedFindIDs.sorted()
        claimedFindIDs = Set(sorted.suffix(FieldFindConstants.maxClaimedFindIDs))
    }

    private func pruneEffects(at date: Date = .now) {
        let pruned = engine.pruneExpiredEffects(activeEffects, at: date)
        if pruned.count != activeEffects.count {
            activeEffects = pruned
            persist()
        }
    }

    private func load() {
        guard let save = JSONFileStore.load(InventorySaveFile.self, from: fileURL),
              save.version == JSONFileStore.currentSchemaVersion else { return }
        stacks = save.stacks.filter { ItemCatalog.definition(for: $0.itemID) != nil && $0.quantity > 0 }
        claimedFindIDs = Set(save.claimedFindIDs)
        claimedFindDayKey = save.claimedFindDayKey
        findsClaimedToday = save.findsClaimedToday
        activeEffects = save.activeEffects
        cartographerPins = save.cartographerPins
        lifetimeFindsCollected = save.lifetimeFindsCollected
    }

    private func persist() {
        JSONFileStore.save(
            InventorySaveFile(
                version: JSONFileStore.currentSchemaVersion,
                stacks: stacks,
                claimedFindIDs: Array(claimedFindIDs).sorted(),
                claimedFindDayKey: claimedFindDayKey,
                findsClaimedToday: findsClaimedToday,
                activeEffects: activeEffects,
                cartographerPins: cartographerPins,
                lifetimeFindsCollected: lifetimeFindsCollected
            ),
            to: fileURL
        )
    }
}
