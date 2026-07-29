import Foundation

// MARK: - Categories & rarity

enum ItemCategory: String, Codable, Sendable, CaseIterable {
    case material
    case boost
    case charge
    case assembled

    var displayName: String {
        switch self {
        case .material: "Material"
        case .boost: "Boost"
        case .charge: "Charge"
        case .assembled: "Assembled"
        }
    }
}

enum ItemRarity: Int, Codable, Sendable, CaseIterable, Comparable {
    case common
    case uncommon
    case rare
    case legendary

    static func < (lhs: ItemRarity, rhs: ItemRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .legendary: "Legendary"
        }
    }
}

enum ItemEffectKind: String, Codable, Sendable, CaseIterable {
    case familiarityBoost
    case discoveryBonus
    case streakOil
    case pathbread
    case fogLantern
    case surveyBeacon
    case trailReroll
    case vaultWhisper
    case cartographerPin
    case echoVial
}

enum ItemActionKind: String, Codable, Sendable, CaseIterable {
    case collect
    case use
    case activate
    case assemble
    case salvage
    case discard
}

// MARK: - Catalog

struct ItemDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let detail: String
    let category: ItemCategory
    let rarity: ItemRarity
    let symbolName: String
    let effectKind: ItemEffectKind?
    /// When set, item is consumed via Use (boost) or Activate (charge).
    let isConsumable: Bool
    let canSalvage: Bool
}

enum ItemCatalog {
    static let all: [ItemDefinition] = materials + boosts + charges + assembled
    static let byID: [String: ItemDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func definition(for id: String) -> ItemDefinition? { byID[id] }

    // Materials / fragments
    static let materials: [ItemDefinition] = [
        ItemDefinition(id: "moss_scrap", name: "Moss Scrap", detail: "Damp green fiber from the edge of the atlas.", category: .material, rarity: .common, symbolName: "leaf.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "cobble_chip", name: "Cobble Chip", detail: "A weathered stone flake underfoot.", category: .material, rarity: .common, symbolName: "hexagon.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "waystone_shard", name: "Waystone Shard", detail: "A cool fragment that hums near new tiles.", category: .material, rarity: .uncommon, symbolName: "diamond.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "brass_rivet", name: "Brass Rivet", detail: "A tiny fastener from some lost instrument.", category: .material, rarity: .uncommon, symbolName: "circle.hexagongrid.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "trail_ribbon", name: "Trail Ribbon", detail: "Faded cloth marking a walker ahead of you.", category: .material, rarity: .common, symbolName: "ribbon.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "fog_lint", name: "Fog Lint", detail: "Soft haze caught on a sleeve.", category: .material, rarity: .common, symbolName: "cloud.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "survey_ink", name: "Survey Ink", detail: "Dark ink that stains mastery charts.", category: .material, rarity: .uncommon, symbolName: "drop.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "compass_filament", name: "Compass Filament", detail: "A hair-thin needle that still seeks north.", category: .material, rarity: .rare, symbolName: "location.north.line.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "sector_dust", name: "Sector Dust", detail: "Fine grit from a frontier sector boundary.", category: .material, rarity: .uncommon, symbolName: "sparkles", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "landmark_fibers", name: "Landmark Fibers", detail: "Threads snagged near a named place.", category: .material, rarity: .rare, symbolName: "mappin.and.ellipse", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "river_pebble", name: "River Pebble", detail: "Smooth stone carried from a wet path.", category: .material, rarity: .common, symbolName: "circle.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "amber_resin", name: "Amber Resin", detail: "Sticky resin that catches atlas dust.", category: .material, rarity: .uncommon, symbolName: "seal.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "copper_wire", name: "Copper Wire", detail: "A short coil useful for instruments.", category: .material, rarity: .uncommon, symbolName: "link", effectKind: nil, isConsumable: false, canSalvage: false),
    ]

    // Consumable boosts
    static let boosts: [ItemDefinition] = [
        ItemDefinition(id: "familiarity_tonic", name: "Familiarity Tonic", detail: "Next 5 revisits grant +50% familiarity XP.", category: .boost, rarity: .uncommon, symbolName: "drop.fill", effectKind: .familiarityBoost, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "discovery_flare", name: "Discovery Flare", detail: "Next new tile grants +25 bonus discovery XP.", category: .boost, rarity: .uncommon, symbolName: "flame.fill", effectKind: .discoveryBonus, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "streak_oil", name: "Streak Oil", detail: "Extends your Frontier combo window once.", category: .boost, rarity: .rare, symbolName: "timer", effectKind: .streakOil, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "pathbread", name: "Pathbread", detail: "A traveler’s bite — grants a little familiarity XP.", category: .boost, rarity: .common, symbolName: "leaf.circle.fill", effectKind: .pathbread, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "echo_vial", name: "Echo Vial", detail: "Re-roll one claimed same-day find onto a nearby tile.", category: .boost, rarity: .rare, symbolName: "waveform.path", effectKind: .echoVial, isConsumable: true, canSalvage: true),
    ]

    // Charges / tools
    static let charges: [ItemDefinition] = [
        ItemDefinition(id: "fog_lantern", name: "Fog Lantern Charge", detail: "Widen the nearby fog wash for a short while.", category: .charge, rarity: .uncommon, symbolName: "light.max", effectKind: .fogLantern, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "survey_beacon", name: "Survey Beacon", detail: "Pulse mastery XP on your tile and discovered neighbors.", category: .charge, rarity: .rare, symbolName: "antenna.radiowaves.left.and.right", effectKind: .surveyBeacon, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "trail_reroll_token", name: "Trail Reroll Token", detail: "Grants +1 free treasure trail reroll.", category: .charge, rarity: .rare, symbolName: "arrow.triangle.2.circlepath", effectKind: .trailReroll, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "vault_whisper", name: "Vault Whisper", detail: "A quiet hint about this week’s vault progress.", category: .charge, rarity: .uncommon, symbolName: "ear.fill", effectKind: .vaultWhisper, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "cartographers_pin", name: "Cartographer’s Pin", detail: "Pin your current tile in the journal (capped).", category: .charge, rarity: .common, symbolName: "pin.fill", effectKind: .cartographerPin, isConsumable: true, canSalvage: false),
    ]

    // Assembled / rare
    static let assembled: [ItemDefinition] = [
        ItemDefinition(id: "waystone_charm", name: "Waystone Charm", detail: "Assembled charm that steadies exploration.", category: .assembled, rarity: .rare, symbolName: "seal.fill", effectKind: .familiarityBoost, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "brass_sextant", name: "Brass Sextant", detail: "Assembled tool that sharpens discovery.", category: .assembled, rarity: .rare, symbolName: "safari.fill", effectKind: .discoveryBonus, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "ribboned_cache_key", name: "Ribboned Cache Key", detail: "Opens a free trail reroll like a cache key.", category: .assembled, rarity: .legendary, symbolName: "key.fill", effectKind: .trailReroll, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "inkbound_lens", name: "Inkbound Lens", detail: "Assembled lens that fuels a survey pulse.", category: .assembled, rarity: .rare, symbolName: "camera.aperture", effectKind: .surveyBeacon, isConsumable: true, canSalvage: true),
        ItemDefinition(id: "sector_talisman", name: "Sector Talisman", detail: "Assembled talisman that oils Frontier streaks.", category: .assembled, rarity: .legendary, symbolName: "shield.lefthalf.filled", effectKind: .streakOil, isConsumable: true, canSalvage: true),
    ]
}

// MARK: - Recipes

struct ItemRecipe: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let outputItemID: String
    let inputs: [String: Int]
    let displayName: String
}

enum ItemRecipes {
    static let all: [ItemRecipe] = [
        ItemRecipe(
            id: "craft_waystone_charm",
            outputItemID: "waystone_charm",
            inputs: ["waystone_shard": 2, "moss_scrap": 3],
            displayName: "Waystone Charm"
        ),
        ItemRecipe(
            id: "craft_brass_sextant",
            outputItemID: "brass_sextant",
            inputs: ["brass_rivet": 2, "compass_filament": 1, "cobble_chip": 2],
            displayName: "Brass Sextant"
        ),
        ItemRecipe(
            id: "craft_ribboned_cache_key",
            outputItemID: "ribboned_cache_key",
            inputs: ["trail_ribbon": 3, "landmark_fibers": 1, "brass_rivet": 1],
            displayName: "Ribboned Cache Key"
        ),
        ItemRecipe(
            id: "craft_inkbound_lens",
            outputItemID: "inkbound_lens",
            inputs: ["survey_ink": 2, "fog_lint": 2, "waystone_shard": 1],
            displayName: "Inkbound Lens"
        ),
        ItemRecipe(
            id: "craft_sector_talisman",
            outputItemID: "sector_talisman",
            inputs: ["sector_dust": 3, "compass_filament": 1, "landmark_fibers": 1],
            displayName: "Sector Talisman"
        ),
    ]

    static func recipe(id: String) -> ItemRecipe? {
        all.first { $0.id == id }
    }
}

// MARK: - Inventory state

struct InventoryStack: Codable, Hashable, Sendable, Identifiable {
    var id: String { itemID }
    let itemID: String
    var quantity: Int
}

struct ActiveItemEffect: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let itemID: String
    let kind: ItemEffectKind
    var remainingCharges: Int
    var expiresAt: Date?
    let startedAt: Date

    var isExpired: Bool {
        if let expiresAt, expiresAt <= Date() { return true }
        if remainingCharges <= 0, kind == .familiarityBoost || kind == .discoveryBonus {
            return true
        }
        return false
    }

    var displayLabel: String {
        switch kind {
        case .familiarityBoost:
            return "Familiarity +\(remainingCharges)"
        case .discoveryBonus:
            return "Discovery flare"
        case .streakOil:
            return "Streak oiled"
        case .fogLantern:
            return "Fog lantern"
        default:
            return ItemCatalog.definition(for: itemID)?.name ?? "Effect"
        }
    }
}

struct FieldFind: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let tileID: String
    let dayKey: String
    let itemID: String
    let quantity: Int
    let isDiscoveryDrop: Bool
}

struct FieldFindPreview: Hashable, Sendable, Identifiable {
    let id: String
    let tileID: String
    let itemID: String
    let rarity: ItemRarity
}

struct ItemPickup: Identifiable, Sendable, Equatable {
    let id: UUID
    let find: FieldFind
    let itemName: String
    let rarity: ItemRarity
    let symbolName: String
}

struct CartographerPin: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let tileID: String
    let note: String
    let pinnedAt: Date
}

struct ItemActionResult: Sendable, Equatable {
    let action: ItemActionKind
    let message: String
    let grantedFamiliarityXP: Int
    let grantedDiscoveryXP: Int
    let outputItemID: String?
    let outputQuantity: Int

    static func message(_ action: ItemActionKind, _ text: String) -> ItemActionResult {
        ItemActionResult(
            action: action,
            message: text,
            grantedFamiliarityXP: 0,
            grantedDiscoveryXP: 0,
            outputItemID: nil,
            outputQuantity: 0
        )
    }
}

enum FieldFindConstants {
    static let maxFindsPerDay = 24
    static let maxMapPreviews = 8
    static let maxClaimedFindIDs = 400
    static let maxCartographerPins = 20
    static let discoveryDropChancePercent = 18
    static let revisitDropChancePercent = 6
    static let rareSparkChancePercent = 8
    static let pathbreadFamiliarityXP = 15
    static let discoveryFlareBonusXP = 25
    static let familiarityBoostMultiplier = 1.5
    static let familiarityBoostCharges = 5
    static let waystoneCharmCharges = 8
    static let fogLanternDuration: TimeInterval = 10 * 60
    static let fogLanternRadiusBonus = 3
    static let surveyBeaconMasteryXP = 12
    static let surveyBeaconNeighborXP = 6
    static let streakOilExtension: TimeInterval = 20 * 60
    static let echoRingRadius = 4
}
