import Foundation

enum FactoryStructureKind: String, Codable, Sendable, CaseIterable {
    case road
    case depot
    case extractor
    case generator
    case processor
    case research
}

enum FactoryPriority: Int, Codable, Sendable, CaseIterable, Comparable {
    case low
    case normal
    case high

    static func < (lhs: FactoryPriority, rhs: FactoryPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

enum FactoryOperationalStatus: String, Sendable {
    case running
    case idle
    case disconnected
    case noPower
    case missingInputs
    case blockedOutput
    case depleted

    var displayName: String {
        switch self {
        case .running: "Running"
        case .idle: "Idle"
        case .disconnected: "Disconnected"
        case .noPower: "No power"
        case .missingInputs: "Missing inputs"
        case .blockedOutput: "Output blocked"
        case .depleted: "Deposit depleted"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "checkmark.circle.fill"
        case .idle: "pause.circle.fill"
        case .disconnected: "point.3.connected.trianglepath.dotted"
        case .noPower: "bolt.slash.fill"
        case .missingInputs: "shippingbox.and.arrow.backward.fill"
        case .blockedOutput: "exclamationmark.triangle.fill"
        case .depleted: "minus.circle.fill"
        }
    }
}

enum FactoryRoadTier: Int, Codable, Sendable, CaseIterable {
    case trail = 1
    case paved = 2
    case waystone = 3

    var capacityPerMinute: Int {
        switch self {
        case .trail: 8
        case .paved: 24
        case .waystone: 60
        }
    }
}

enum FactoryDepositKind: String, Codable, Sendable, CaseIterable {
    case cobble
    case moss
    case copper
    case amber
    case waystone
    case empty

    var displayName: String {
        switch self {
        case .cobble: "Cobble seam"
        case .moss: "Moss bed"
        case .copper: "Copper vein"
        case .amber: "Amber spring"
        case .waystone: "Waystone seam"
        case .empty: "No deposit"
        }
    }

    var outputItemID: String? {
        switch self {
        case .cobble: "cobble_chip"
        case .moss: "moss_scrap"
        case .copper: "copper_ore"
        case .amber: "amber_resin"
        case .waystone: "waystone_shard"
        case .empty: nil
        }
    }
}

struct FactoryDeposit: Sendable, Equatable {
    let kind: FactoryDepositKind
    let capacity: Int
}

struct FactoryNetworkMetrics: Sendable, Equatable, Identifiable {
    var id: String { networkID }
    let networkID: String
    let powerSupply: Int
    let powerDemand: Int
    let poweredBuildingIDs: Set<String>
    let storedItemCount: Int
}

struct FactoryStructureDefinition: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let detail: String
    let kind: FactoryStructureKind
    let kitItemID: String
    let symbolName: String
    let powerDemand: Int
    let powerSupply: Int
    let storageCapacity: Int
    let roadTier: FactoryRoadTier?
    let allowedRecipeIDs: [String]
    let requiredResearchID: String?
}

struct PlacedFactoryStructure: Codable, Hashable, Sendable, Identifiable {
    var id: String { tileID }
    let tileID: String
    var definitionID: String
    var tier: Int
    var inputBuffer: [String: Int]
    var outputBuffer: [String: Int]
    var selectedRecipeID: String?
    var recipeProgressMinutes: Int
    var extractedUnits: Int
    var priority: FactoryPriority
    var fueledMinutes: Int
    let placedAt: Date
}

struct FactoryState: Codable, Sendable, Equatable {
    var structures: [String: PlacedFactoryStructure]
    var unlockedResearchIDs: Set<String>
    var lastSimulatedAt: Date
    var lifetimeProduced: [String: Int]

    static func empty(at date: Date = .now) -> FactoryState {
        FactoryState(
            structures: [:],
            unlockedResearchIDs: ["foundations"],
            lastSimulatedAt: date,
            lifetimeProduced: [:]
        )
    }
}

struct FactoryResearchDefinition: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let detail: String
    let insightCost: Int
    let explorerLevel: Int
    let prerequisiteIDs: Set<String>
}

enum FactoryResearchCatalog {
    static let all: [FactoryResearchDefinition] = [
        .init(id: "foundations", name: "Foundations", detail: "Starter roads, depots, extraction, power, refining, and research.", insightCost: 0, explorerLevel: 1, prerequisiteIDs: []),
        .init(id: "logistics_1", name: "Logistics I", detail: "Depot-assisted construction and paved roads.", insightCost: 10, explorerLevel: 5, prerequisiteIDs: ["foundations"]),
        .init(id: "mechanics", name: "Mechanics", detail: "Gearworks and brass mechanisms.", insightCost: 15, explorerLevel: 8, prerequisiteIDs: ["logistics_1"]),
        .init(id: "automation", name: "Automation", detail: "Assembly halls and automated construction kits.", insightCost: 25, explorerLevel: 12, prerequisiteIDs: ["mechanics"]),
        .init(id: "power_2", name: "Power II", detail: "Tier-two waystone dynamos.", insightCost: 30, explorerLevel: 15, prerequisiteIDs: ["mechanics"]),
        .init(id: "logistics_2", name: "Logistics II", detail: "Waystone roads and grand depots.", insightCost: 40, explorerLevel: 20, prerequisiteIDs: ["automation"]),
        .init(id: "extraction_2", name: "Extraction II", detail: "Tier-two outposts with doubled extraction.", insightCost: 50, explorerLevel: 25, prerequisiteIDs: ["power_2"]),
    ]

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

enum FactoryCatalog {
    static let definitions: [FactoryStructureDefinition] = [
        .init(id: "trail_road", name: "Trail Road", detail: "Carries 8 item units per minute.", kind: .road, kitItemID: "trail_road_kit", symbolName: "road.lanes", powerDemand: 0, powerSupply: 0, storageCapacity: 0, roadTier: .trail, allowedRecipeIDs: [], requiredResearchID: nil),
        .init(id: "paved_road", name: "Paved Road", detail: "Carries 24 item units per minute.", kind: .road, kitItemID: "paved_road_kit", symbolName: "road.lanes.curved.left", powerDemand: 0, powerSupply: 0, storageCapacity: 0, roadTier: .paved, allowedRecipeIDs: [], requiredResearchID: "logistics_1"),
        .init(id: "waystone_road", name: "Waystone Road", detail: "Carries 60 item units per minute.", kind: .road, kitItemID: "waystone_road_kit", symbolName: "point.topleft.down.to.point.bottomright.curvepath.fill", powerDemand: 0, powerSupply: 0, storageCapacity: 0, roadTier: .waystone, allowedRecipeIDs: [], requiredResearchID: "logistics_2"),
        .init(id: "trailhead_depot", name: "Trailhead Depot", detail: "Stores 200 items for a connected road network.", kind: .depot, kitItemID: "trailhead_depot_kit", symbolName: "shippingbox.fill", powerDemand: 0, powerSupply: 0, storageCapacity: 200, roadTier: nil, allowedRecipeIDs: [], requiredResearchID: nil),
        .init(id: "grand_depot", name: "Grand Depot", detail: "Stores 1,000 items for a connected road network.", kind: .depot, kitItemID: "grand_depot_kit", symbolName: "shippingbox.and.arrow.backward.fill", powerDemand: 0, powerSupply: 0, storageCapacity: 1_000, roadTier: nil, allowedRecipeIDs: [], requiredResearchID: "logistics_2"),
        .init(id: "gathering_outpost", name: "Gathering Outpost", detail: "Extracts the deposit beneath its hex.", kind: .extractor, kitItemID: "gathering_outpost_kit", symbolName: "pickaxe", powerDemand: 2, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: [], requiredResearchID: nil),
        .init(id: "waystone_dynamo", name: "Waystone Dynamo", detail: "Burns amber resin to power a road network.", kind: .generator, kitItemID: "waystone_dynamo_kit", symbolName: "bolt.fill", powerDemand: 0, powerSupply: 20, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: [], requiredResearchID: nil),
        .init(id: "atlas_refinery", name: "Atlas Refinery", detail: "Refines raw atlas materials.", kind: .processor, kitItemID: "atlas_refinery_kit", symbolName: "flame.fill", powerDemand: 4, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: ["refine_stone_block", "refine_copper_wire", "refine_composite_fiber", "refine_survey_ink", "refine_waystone_plate"], requiredResearchID: nil),
        .init(id: "research_observatory", name: "Research Observatory", detail: "Binds field notes and mechanisms into Atlas Insights.", kind: .research, kitItemID: "research_observatory_kit", symbolName: "scope", powerDemand: 6, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: ["bind_field_insight", "bind_atlas_insight"], requiredResearchID: nil),
        .init(id: "gearworks", name: "Gearworks", detail: "Produces rivets and brass mechanisms.", kind: .processor, kitItemID: "gearworks_kit", symbolName: "gearshape.2.fill", powerDemand: 6, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: ["forge_brass_rivets", "forge_mechanism"], requiredResearchID: "mechanics"),
        .init(id: "assembly_hall", name: "Assembly Hall", detail: "Automates advanced construction kits.", kind: .processor, kitItemID: "assembly_hall_kit", symbolName: "building.2.fill", powerDemand: 8, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: ["assemble_paved_road", "assemble_waystone_road", "assemble_gearworks", "assemble_hall", "assemble_grand_depot"], requiredResearchID: "automation"),
    ]

    static let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
    static let byKitItemID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.kitItemID, $0) })
}

enum FactoryRecipeCatalog {
    static let handRecipes: [RecipeDefinition] = [
        hand("craft_trail_road", "Trail Road Kit", ["cobble_chip": 2, "moss_scrap": 1], "trail_road_kit"),
        hand("craft_trailhead_depot", "Trailhead Depot Kit", ["cobble_chip": 4, "brass_rivet": 2, "trail_ribbon": 2], "trailhead_depot_kit"),
        hand("craft_gathering_outpost", "Gathering Outpost Kit", ["cobble_chip": 5, "brass_rivet": 3, "waystone_shard": 1], "gathering_outpost_kit"),
        hand("craft_waystone_dynamo", "Waystone Dynamo Kit", ["cobble_chip": 6, "copper_wire": 3, "amber_resin": 2], "waystone_dynamo_kit"),
        hand("craft_atlas_refinery", "Atlas Refinery Kit", ["cobble_chip": 8, "brass_rivet": 4, "copper_wire": 2], "atlas_refinery_kit"),
        hand("craft_research_observatory", "Research Observatory Kit", ["cobble_chip": 6, "waystone_shard": 2, "survey_ink": 2, "copper_wire": 2], "research_observatory_kit"),
    ]

    static let machineRecipes: [RecipeDefinition] = [
        recipe("refine_stone_block", "Cut Stone Block", ["cobble_chip": 2], ["stone_block": 1], 2, ["atlas_refinery"]),
        recipe("refine_copper_wire", "Draw Copper Wire", ["copper_ore": 1, "amber_resin": 1], ["copper_wire": 2], 3, ["atlas_refinery"]),
        recipe("refine_composite_fiber", "Bind Composite Fiber", ["moss_scrap": 2, "amber_resin": 1], ["composite_fiber": 1], 2, ["atlas_refinery"]),
        recipe("refine_survey_ink", "Distill Survey Ink", ["moss_scrap": 2, "amber_resin": 1], ["survey_ink": 1], 3, ["atlas_refinery"]),
        recipe("refine_waystone_plate", "Cut Waystone Plate", ["waystone_shard": 2], ["waystone_plate": 1], 3, ["atlas_refinery"]),
        recipe("forge_brass_rivets", "Forge Brass Rivets", ["copper_wire": 1, "stone_block": 1], ["brass_rivet": 2], 3, ["gearworks"], "mechanics"),
        recipe("forge_mechanism", "Assemble Brass Mechanism", ["brass_rivet": 2, "copper_wire": 1, "composite_fiber": 1], ["mechanism": 1], 4, ["gearworks"], "mechanics"),
        recipe("bind_field_insight", "Bind Field Insight", ["survey_ink": 1, "sector_dust": 1, "waystone_shard": 1], ["atlas_insight": 1], 8, ["research_observatory"]),
        recipe("bind_atlas_insight", "Bind Mechanized Insight", ["survey_ink": 1, "mechanism": 1, "waystone_plate": 1], ["atlas_insight": 1], 5, ["research_observatory"], "mechanics"),
        recipe("assemble_paved_road", "Assemble Paved Roads", ["stone_block": 1, "composite_fiber": 1], ["paved_road_kit": 2], 5, ["assembly_hall"], "automation"),
        recipe("assemble_waystone_road", "Assemble Waystone Roads", ["stone_block": 1, "waystone_plate": 1, "mechanism": 1], ["waystone_road_kit": 2], 8, ["assembly_hall"], "logistics_2"),
        recipe("assemble_gearworks", "Assemble Gearworks Kit", ["stone_block": 6, "brass_rivet": 6, "mechanism": 2], ["gearworks_kit": 1], 10, ["assembly_hall"], "automation"),
        recipe("assemble_hall", "Assemble Hall Kit", ["stone_block": 8, "brass_rivet": 8, "mechanism": 4, "waystone_plate": 2], ["assembly_hall_kit": 1], 15, ["assembly_hall"], "automation"),
        recipe("assemble_grand_depot", "Assemble Grand Depot Kit", ["stone_block": 10, "brass_rivet": 8, "mechanism": 4], ["grand_depot_kit": 1], 12, ["assembly_hall"], "logistics_2"),
    ]

    static let all = handRecipes + machineRecipes
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    private static func hand(_ id: String, _ name: String, _ inputs: [String: Int], _ output: String) -> RecipeDefinition {
        recipe(id, name, inputs, [output: 1], 0, ["hand"])
    }

    private static func recipe(
        _ id: String,
        _ name: String,
        _ inputs: [String: Int],
        _ outputs: [String: Int],
        _ minutes: Int,
        _ producers: [String],
        _ research: String? = nil
    ) -> RecipeDefinition {
        RecipeDefinition(
            id: id,
            displayName: name,
            inputs: inputs.map { ItemAmount(itemID: $0.key, quantity: $0.value) }.sorted { $0.itemID < $1.itemID },
            outputs: outputs.map { ItemAmount(itemID: $0.key, quantity: $0.value) }.sorted { $0.itemID < $1.itemID },
            durationMinutes: minutes,
            producerIDs: producers,
            requiredResearchID: research
        )
    }
}
