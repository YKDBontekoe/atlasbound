import Foundation

// MARK: - Categories & rarity

enum ItemCategory: String, Codable, Sendable, CaseIterable {
    case material
    case component
    case boost
    case charge
    case assembled
    case construction

    var displayName: String {
        switch self {
        case .material: "Material"
        case .component: "Component"
        case .boost: "Boost"
        case .charge: "Charge"
        case .assembled: "Assembled"
        case .construction: "Construction"
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
    static let all: [ItemDefinition] = materials + components + boosts + charges + assembled + construction
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
        ItemDefinition(id: "copper_ore", name: "Copper Ore", detail: "Raw copper-bearing stone from an atlas deposit.", category: .material, rarity: .common, symbolName: "circle.hexagongrid.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "water", name: "Raw Water", detail: "Collected water awaiting treatment.", category: .material, rarity: .common, symbolName: "drop.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "seed_stock", name: "Seed Stock", detail: "A hardy seed reserve for an atlas field.", category: .material, rarity: .common, symbolName: "leaf.circle.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "grain", name: "Atlas Grain", detail: "A durable crop harvested from a field plot.", category: .material, rarity: .common, symbolName: "square.grid.2x2.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "crop_fiber", name: "Crop Fiber", detail: "Strong plant fiber for resilient construction.", category: .material, rarity: .uncommon, symbolName: "leaf.fill", effectKind: nil, isConsumable: false, canSalvage: false),
    ]

    static let components: [ItemDefinition] = [
        ItemDefinition(id: "stone_block", name: "Stone Block", detail: "Refined cobble for permanent works.", category: .component, rarity: .common, symbolName: "square.stack.3d.up.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "composite_fiber", name: "Composite Fiber", detail: "Resin-bound moss fiber for mechanisms and roads.", category: .component, rarity: .uncommon, symbolName: "point.3.filled.connected.trianglepath.dotted", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "waystone_plate", name: "Waystone Plate", detail: "A resonant plate cut from paired shards.", category: .component, rarity: .rare, symbolName: "diamond.inset.filled", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "mechanism", name: "Brass Mechanism", detail: "A compact drive for automated atlas works.", category: .component, rarity: .rare, symbolName: "gearshape.2.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "atlas_insight", name: "Atlas Insight", detail: "A bound observation consumed by factory research.", category: .component, rarity: .rare, symbolName: "lightbulb.max.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "treated_water", name: "Treated Water", detail: "Clean water ready for irrigation.", category: .component, rarity: .common, symbolName: "drop.circle.fill", effectKind: nil, isConsumable: false, canSalvage: false),
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

    static let construction: [ItemDefinition] = [
        ItemDefinition(id: "trail_road_kit", name: "Trail Road Kit", detail: "Marks one atlas hex as a logistics road.", category: .construction, rarity: .common, symbolName: "road.lanes", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "paved_road_kit", name: "Paved Road Kit", detail: "Upgrades a trail road for greater throughput.", category: .construction, rarity: .uncommon, symbolName: "road.lanes.curved.left", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "waystone_road_kit", name: "Waystone Road Kit", detail: "Upgrades a paved road into a high-capacity route.", category: .construction, rarity: .rare, symbolName: "point.topleft.down.to.point.bottomright.curvepath.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "trailhead_depot_kit", name: "Trailhead Depot Kit", detail: "Places a compact logistics depot.", category: .construction, rarity: .common, symbolName: "shippingbox.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "gathering_outpost_kit", name: "Gathering Outpost Kit", detail: "Places an extractor on a revealed deposit.", category: .construction, rarity: .uncommon, symbolName: "pickaxe", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "waystone_dynamo_kit", name: "Waystone Dynamo Kit", detail: "Places an amber-fueled power source.", category: .construction, rarity: .uncommon, symbolName: "bolt.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "atlas_refinery_kit", name: "Atlas Refinery Kit", detail: "Places a refinery for raw materials.", category: .construction, rarity: .uncommon, symbolName: "flame.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "research_observatory_kit", name: "Research Observatory Kit", detail: "Places an observatory that binds Atlas Insights.", category: .construction, rarity: .rare, symbolName: "scope", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "gearworks_kit", name: "Gearworks Kit", detail: "Places a workshop for brass mechanisms.", category: .construction, rarity: .rare, symbolName: "gearshape.2.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "assembly_hall_kit", name: "Assembly Hall Kit", detail: "Places an automated construction hall.", category: .construction, rarity: .legendary, symbolName: "building.2.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "grand_depot_kit", name: "Grand Depot Kit", detail: "Places a high-capacity logistics depot.", category: .construction, rarity: .legendary, symbolName: "shippingbox.and.arrow.backward.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "rain_catcher_kit", name: "Rain Catcher Kit", detail: "Places a weather-aware water collector.", category: .construction, rarity: .uncommon, symbolName: "cloud.rain.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "reservoir_kit", name: "Reservoir Kit", detail: "Places a water buffer and treatment works.", category: .construction, rarity: .rare, symbolName: "drop.triangle.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "solar_array_kit", name: "Solar Array Kit", detail: "Places a weather-aware solar generator.", category: .construction, rarity: .uncommon, symbolName: "sun.max.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "wind_turbine_kit", name: "Wind Turbine Kit", detail: "Places a wind-powered generator.", category: .construction, rarity: .uncommon, symbolName: "wind", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "field_plot_kit", name: "Field Plot Kit", detail: "Places an exposed crop plot.", category: .construction, rarity: .uncommon, symbolName: "leaf.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "greenhouse_kit", name: "Greenhouse Kit", detail: "Places a protected crop building.", category: .construction, rarity: .rare, symbolName: "building.columns.fill", effectKind: nil, isConsumable: false, canSalvage: false),
        ItemDefinition(id: "deep_mine_kit", name: "Deep Mine Kit", detail: "Places a high-capacity drill on a deposit.", category: .construction, rarity: .rare, symbolName: "mountain.2.fill", effectKind: nil, isConsumable: false, canSalvage: false),
    ]
}

// MARK: - Recipes

struct ItemAmount: Codable, Hashable, Sendable, Identifiable {
    var id: String { itemID }
    let itemID: String
    let quantity: Int
}

struct RecipeDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let inputs: [ItemAmount]
    let outputs: [ItemAmount]
    let durationMinutes: Int
    let producerIDs: [String]
    let requiredResearchID: String?

    var isHandCraftable: Bool { producerIDs.contains("hand") }
    var primaryOutput: ItemAmount? { outputs.first }
}

enum ItemRecipes {
    static let all: [RecipeDefinition] = [
        RecipeDefinition(
            id: "craft_waystone_charm",
            displayName: "Waystone Charm",
            inputs: [.init(itemID: "waystone_shard", quantity: 2), .init(itemID: "moss_scrap", quantity: 3)],
            outputs: [.init(itemID: "waystone_charm", quantity: 1)],
            durationMinutes: 0, producerIDs: ["hand"], requiredResearchID: nil
        ),
        RecipeDefinition(
            id: "craft_brass_sextant",
            displayName: "Brass Sextant",
            inputs: [.init(itemID: "brass_rivet", quantity: 2), .init(itemID: "compass_filament", quantity: 1), .init(itemID: "cobble_chip", quantity: 2)],
            outputs: [.init(itemID: "brass_sextant", quantity: 1)],
            durationMinutes: 0, producerIDs: ["hand"], requiredResearchID: nil
        ),
        RecipeDefinition(
            id: "craft_ribboned_cache_key",
            displayName: "Ribboned Cache Key",
            inputs: [.init(itemID: "trail_ribbon", quantity: 3), .init(itemID: "landmark_fibers", quantity: 1), .init(itemID: "brass_rivet", quantity: 1)],
            outputs: [.init(itemID: "ribboned_cache_key", quantity: 1)],
            durationMinutes: 0, producerIDs: ["hand"], requiredResearchID: nil
        ),
        RecipeDefinition(
            id: "craft_inkbound_lens",
            displayName: "Inkbound Lens",
            inputs: [.init(itemID: "survey_ink", quantity: 2), .init(itemID: "fog_lint", quantity: 2), .init(itemID: "waystone_shard", quantity: 1)],
            outputs: [.init(itemID: "inkbound_lens", quantity: 1)],
            durationMinutes: 0, producerIDs: ["hand"], requiredResearchID: nil
        ),
        RecipeDefinition(
            id: "craft_sector_talisman",
            displayName: "Sector Talisman",
            inputs: [.init(itemID: "sector_dust", quantity: 3), .init(itemID: "compass_filament", quantity: 1), .init(itemID: "landmark_fibers", quantity: 1)],
            outputs: [.init(itemID: "sector_talisman", quantity: 1)],
            durationMinutes: 0, producerIDs: ["hand"], requiredResearchID: nil
        ),
    ] + FactoryRecipeCatalog.handRecipes

    static func recipe(id: String) -> RecipeDefinition? {
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
