import Foundation

enum FactoryStructureKind: String, Codable, Sendable, CaseIterable {
    case road
    case depot
    case extractor
    case generator
    case processor
    case research
    case water
    case farm
    case renewable
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
        .init(id: "logistics_3", name: "Logistics III", detail: "Arterial logistics and denser depot throughput.", insightCost: 60, explorerLevel: 30, prerequisiteIDs: ["logistics_2"]),
        .init(id: "automation_2", name: "Automation II", detail: "Faster assembly halls and kit lines.", insightCost: 70, explorerLevel: 35, prerequisiteIDs: ["automation", "logistics_3"]),
        .init(id: "power_3", name: "Power III", detail: "Tier-three dynamos with greater supply.", insightCost: 80, explorerLevel: 40, prerequisiteIDs: ["power_2", "automation_2"]),
        .init(id: "extraction_3", name: "Extraction III", detail: "Tier-three outposts with triple extraction.", insightCost: 90, explorerLevel: 45, prerequisiteIDs: ["extraction_2", "power_3"]),
        .init(id: "waterworks", name: "Waterworks", detail: "Unlocks catchment, reservoirs, and treated water.", insightCost: 35, explorerLevel: 14, prerequisiteIDs: ["logistics_1"]),
        .init(id: "renewables", name: "Renewables", detail: "Unlocks solar arrays and wind turbines.", insightCost: 45, explorerLevel: 18, prerequisiteIDs: ["power_2"]),
        .init(id: "agriculture", name: "Agriculture", detail: "Unlocks fields, greenhouses, and crop production.", insightCost: 50, explorerLevel: 20, prerequisiteIDs: ["waterworks"]),
        .init(id: "deep_extraction", name: "Deep Extraction", detail: "Unlocks high-capacity mines and ore processing.", insightCost: 65, explorerLevel: 28, prerequisiteIDs: ["extraction_2", "renewables"]),
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
        .init(id: "rain_catcher", name: "Rain Catcher", detail: "Collects water from regional precipitation.", kind: .water, kitItemID: "rain_catcher_kit", symbolName: "cloud.rain.fill", powerDemand: 1, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: [], requiredResearchID: "waterworks"),
        .init(id: "reservoir", name: "Reservoir", detail: "Buffers water for farms and treatment.", kind: .water, kitItemID: "reservoir_kit", symbolName: "drop.triangle.fill", powerDemand: 1, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: ["treat_water"], requiredResearchID: "waterworks"),
        .init(id: "solar_array", name: "Solar Array", detail: "Generates power from clear skies.", kind: .renewable, kitItemID: "solar_array_kit", symbolName: "sun.max.fill", powerDemand: 0, powerSupply: 18, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: [], requiredResearchID: "renewables"),
        .init(id: "wind_turbine", name: "Wind Turbine", detail: "Generates power from wind and storms.", kind: .renewable, kitItemID: "wind_turbine_kit", symbolName: "wind", powerDemand: 0, powerSupply: 16, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: [], requiredResearchID: "renewables"),
        .init(id: "field_plot", name: "Field Plot", detail: "Turns water and seed stock into seasonal crops.", kind: .farm, kitItemID: "field_plot_kit", symbolName: "leaf.fill", powerDemand: 2, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: ["grow_grain", "grow_fiber"], requiredResearchID: "agriculture"),
        .init(id: "greenhouse", name: "Greenhouse", detail: "Protected crop production with weather resilience.", kind: .farm, kitItemID: "greenhouse_kit", symbolName: "building.columns.fill", powerDemand: 5, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: ["grow_grain", "grow_fiber"], requiredResearchID: "agriculture"),
        .init(id: "deep_mine", name: "Deep Mine", detail: "Extracts a revealed deposit with a high-capacity drill.", kind: .extractor, kitItemID: "deep_mine_kit", symbolName: "mountain.2.fill", powerDemand: 7, powerSupply: 0, storageCapacity: 0, roadTier: nil, allowedRecipeIDs: [], requiredResearchID: "deep_extraction"),
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
        hand("craft_rain_catcher", "Rain Catcher Kit", ["cobble_chip": 4, "copper_wire": 2, "moss_scrap": 2], "rain_catcher_kit"),
        hand("craft_reservoir", "Reservoir Kit", ["stone_block": 5, "copper_wire": 3, "waystone_shard": 1], "reservoir_kit"),
        hand("craft_solar_array", "Solar Array Kit", ["stone_block": 3, "copper_wire": 4, "amber_resin": 1], "solar_array_kit"),
        hand("craft_wind_turbine", "Wind Turbine Kit", ["stone_block": 3, "copper_wire": 3, "mechanism": 1], "wind_turbine_kit"),
        hand("craft_field_plot", "Field Plot Kit", ["cobble_chip": 3, "moss_scrap": 3, "brass_rivet": 2], "field_plot_kit"),
        hand("craft_greenhouse", "Greenhouse Kit", ["stone_block": 5, "composite_fiber": 3, "copper_wire": 3], "greenhouse_kit"),
        hand("craft_deep_mine", "Deep Mine Kit", ["stone_block": 8, "mechanism": 3, "waystone_plate": 1], "deep_mine_kit"),
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
        recipe("treat_water", "Treat Water", ["water": 2, "moss_scrap": 1], ["treated_water": 2], 3, ["reservoir"], "waterworks"),
        recipe("grow_grain", "Grow Grain", ["treated_water": 1, "seed_stock": 1], ["grain": 2], 12, ["field_plot", "greenhouse"], "agriculture"),
        recipe("grow_fiber", "Grow Fiber", ["treated_water": 1, "seed_stock": 1], ["crop_fiber": 2], 10, ["field_plot", "greenhouse"], "agriculture"),
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
