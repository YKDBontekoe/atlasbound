import Foundation
import CoreLocation
import Combine

@MainActor
final class FactoryController: ObservableObject {
    @Published var isBuildModeActive = false
    @Published var selectedBuildDefinitionID: String?
    @Published var selectedStructureID: String?
    @Published var latestMessage: String?

    let store: FactoryStore
    let tileStore: TileStore
    let inventoryStore: InventoryStore
    let skillStore: SkillStore

    private let constructionEngine = ConstructionEngine()
    private let networkEngine = FactoryNetworkEngine()
    private let simulationEngine = FactorySimulationEngine()
    private var playerLocation: CLLocation?
    private var cachedTopologyKey = ""
    private var cachedNetworks: [FactoryNetworkSnapshot] = []

    init(
        store: FactoryStore,
        tileStore: TileStore,
        inventoryStore: InventoryStore,
        skillStore: SkillStore? = nil
    ) {
        self.store = store
        self.tileStore = tileStore
        self.inventoryStore = inventoryStore
        self.skillStore = skillStore ?? SkillStore()
    }

    var structures: [PlacedFactoryStructure] {
        store.structures.values.sorted { $0.tileID < $1.tileID }
    }

    var selectedBuildDefinition: FactoryStructureDefinition? {
        selectedBuildDefinitionID.flatMap { FactoryCatalog.byID[$0] }
    }

    var explorerLevel: Int {
        ExplorerProgressionEngine().level(
            forTotalXP: tileStore.discoveryXPTotal + tileStore.familiarityXPTotal
        )
    }

    /// Insight cost after Artifice thrift (foundations stay free).
    func effectiveInsightCost(for research: FactoryResearchDefinition) -> Int {
        guard research.insightCost > 0 else { return 0 }
        let multiplier = max(0.5, skillStore.modifiers().insightCostMultiplier)
        return max(1, Int((Double(research.insightCost) * multiplier).rounded()))
    }

    var networks: [FactoryNetworkSnapshot] {
        let key = store.structures.values
            .map { "\($0.tileID):\($0.definitionID)" }
            .sorted()
            .joined(separator: "|")
        if key != cachedTopologyKey {
            cachedTopologyKey = key
            cachedNetworks = networkEngine.networks(
                structures: store.structures,
                tileEngine: tileStore.tileEngine
            )
        }
        return cachedNetworks
    }

    var totalPowerSupply: Int {
        networkMetrics.reduce(0) { $0 + $1.powerSupply }
    }

    var totalPowerDemand: Int {
        networkMetrics.reduce(0) { $0 + $1.powerDemand }
    }

    var networkMetrics: [FactoryNetworkMetrics] {
        networks.map(metrics(for:))
    }

    func availableItemCount(_ itemID: String) -> Int {
        totalAvailableItem(itemID)
    }

    func status(for structure: PlacedFactoryStructure) -> FactoryOperationalStatus {
        guard let definition = FactoryCatalog.byID[structure.definitionID] else { return .idle }
        if definition.kind == .road || definition.kind == .depot {
            return .running
        }
        guard let network = networks.first(where: { $0.buildingTileIDs.contains(structure.tileID) }) else {
            return .disconnected
        }
        if definition.kind == .extractor {
            let deposit = constructionEngine.deposit(for: structure.tileID)
            if structure.extractedUnits >= deposit.capacity { return .depleted }
        }
        if structure.outputBuffer.values.reduce(0, +) >= FactorySimulationEngine.defaultBufferCapacity {
            return .blockedOutput
        }
        let networkMetric = metrics(for: network)
        if definition.powerDemand > 0,
           !networkMetric.poweredBuildingIDs.contains(structure.tileID) {
            return .noPower
        }
        if definition.kind == .generator {
            return structure.fueledMinutes > 0 || availableItemCount("amber_resin", in: network) > 0
                ? .running
                : .missingInputs
        }
        if let recipeID = structure.selectedRecipeID,
           let recipe = FactoryRecipeCatalog.byID[recipeID] {
            let available = Dictionary(grouping: recipe.inputs, by: \.itemID).mapValues {
                $0.reduce(0) { $0 + $1.quantity }
            }
            let hasAnyMissing = available.contains { itemID, needed in
                (structure.inputBuffer[itemID] ?? 0) + availableItemCount(itemID, in: network) < needed
            }
            if hasAnyMissing { return .missingInputs }
            return .running
        }
        return definition.kind == .extractor ? .running : .idle
    }

    private func metrics(for network: FactoryNetworkSnapshot) -> FactoryNetworkMetrics {
        let generatorIDs = network.buildingTileIDs.filter {
            store.structures[$0].flatMap { FactoryCatalog.byID[$0.definitionID] }?.kind == .generator
        }
        let amberAvailable = availableItemCount("amber_resin", in: network)
        var unreservedAmber = amberAvailable
        var supply = 0
        for generatorID in generatorIDs.sorted() {
            guard let generator = store.structures[generatorID],
                  let definition = FactoryCatalog.byID[generator.definitionID] else { continue }
            let canRun: Bool
            if generator.fueledMinutes > 0 || (generator.inputBuffer["amber_resin"] ?? 0) > 0 {
                canRun = true
            } else if unreservedAmber > 0 {
                canRun = true
                unreservedAmber -= 1
            } else {
                canRun = false
            }
            if canRun {
                supply += generator.tier >= 2 ? 50 : definition.powerSupply
            }
        }

        let consumers = network.buildingTileIDs.compactMap { tileID -> (String, FactoryPriority, Int)? in
            guard let structure = store.structures[tileID],
                  let definition = FactoryCatalog.byID[structure.definitionID],
                  definition.powerDemand > 0 else { return nil }
            return (tileID, structure.priority, definition.powerDemand)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0 < $1.0
        }
        var availablePower = supply
        var powered: Set<String> = []
        for consumer in consumers where availablePower >= consumer.2 {
            availablePower -= consumer.2
            powered.insert(consumer.0)
        }
        let stored = network.buildingTileIDs.reduce(0) { total, tileID in
            guard let structure = store.structures[tileID],
                  FactoryCatalog.byID[structure.definitionID]?.kind == .depot else { return total }
            return total + structure.outputBuffer.values.reduce(0, +)
        }
        return FactoryNetworkMetrics(
            networkID: network.id,
            powerSupply: supply,
            powerDemand: consumers.reduce(0) { $0 + $1.2 },
            poweredBuildingIDs: powered,
            storedItemCount: stored
        )
    }

    private func availableItemCount(_ itemID: String, in network: FactoryNetworkSnapshot) -> Int {
        network.buildingTileIDs.reduce(0) { total, tileID in
            guard let structure = store.structures[tileID],
                  FactoryCatalog.byID[structure.definitionID]?.kind == .depot else { return total }
            return total + (structure.outputBuffer[itemID] ?? 0)
        }
    }

    func updatePlayerLocation(_ location: CLLocation?) {
        playerLocation = location
    }

    func selectBuildDefinition(_ definitionID: String?) {
        selectedBuildDefinitionID = definitionID
        isBuildModeActive = definitionID != nil
        latestMessage = nil
    }

    func validation(for tileID: String, now: Date = .now) -> ConstructionValidation {
        guard let definition = selectedBuildDefinition else {
            return .denied("Choose a building or road kit.")
        }
        if let existing = store.structures[tileID],
           let existingDefinition = FactoryCatalog.byID[existing.definitionID],
           definition.kind == .road,
           existingDefinition.kind == .road {
            return validateRoadUpgrade(
                existing: existingDefinition,
                replacement: definition,
                tileID: tileID,
                now: now
            )
        }
        let available = availableConstructionItemCount(definition.kitItemID, near: tileID)
        return constructionEngine.validatePlacement(
            definition: definition,
            targetTile: tileStore.tiles[tileID],
            playerTile: playerLocation.map { tileStore.tileEngine.axialCoordinate(for: $0.coordinate) },
            locationTimestamp: playerLocation?.timestamp,
            now: now,
            structures: store.structures,
            unlockedResearchIDs: store.unlockedResearchIDs,
            availableKitCount: available,
            tileEngine: tileStore.tileEngine
        )
    }

    @discardableResult
    func placeSelected(at tileID: String, now: Date = .now) -> Bool {
        guard let definition = selectedBuildDefinition else { return false }
        let validation = validation(for: tileID, now: now)
        guard validation.isAllowed else {
            latestMessage = validation.message
            return false
        }
        if let existing = store.structures[tileID],
           let current = FactoryCatalog.byID[existing.definitionID],
           current.kind == .road, definition.kind == .road {
            return applyRoadUpgrade(definition, at: tileID)
        }
        guard consumeConstructionItem(definition.kitItemID, near: tileID) else {
            latestMessage = "The required kit is no longer available."
            return false
        }
        let structure = PlacedFactoryStructure(
            tileID: tileID,
            definitionID: definition.id,
            tier: 1,
            inputBuffer: [:],
            outputBuffer: [:],
            selectedRecipeID: definition.allowedRecipeIDs.first,
            recipeProgressMinutes: 0,
            extractedUnits: 0,
            priority: .normal,
            fueledMinutes: 0,
            placedAt: now
        )
        store.update { $0.structures[tileID] = structure }
        latestMessage = "Placed \(definition.name)."
        if definition.kind != .road {
            isBuildModeActive = false
            selectedBuildDefinitionID = nil
        }
        return true
    }

    func advance(to date: Date = .now) {
        let next = simulationEngine.advance(
            state: store.state,
            to: date,
            tileEngine: tileStore.tileEngine,
            speedMultiplier: skillStore.modifiers().factorySpeedMultiplier
        )
        store.replaceState(next)
    }

    func selectRecipe(_ recipeID: String?, for tileID: String) {
        guard var structure = store.structures[tileID],
              let definition = FactoryCatalog.byID[structure.definitionID],
              recipeID.map(definition.allowedRecipeIDs.contains) ?? true else { return }
        structure.selectedRecipeID = recipeID
        structure.recipeProgressMinutes = 0
        store.update { $0.structures[tileID] = structure }
        advance()
    }

    func setPriority(_ priority: FactoryPriority, for tileID: String) {
        guard var structure = store.structures[tileID] else { return }
        structure.priority = priority
        store.update { $0.structures[tileID] = structure }
    }

    @discardableResult
    func upgradeStructure(at tileID: String) -> Bool {
        guard var structure = store.structures[tileID],
              let definition = FactoryCatalog.byID[structure.definitionID],
              definition.kind == .extractor || definition.kind == .generator else { return false }
        let nextTier = structure.tier + 1
        let researchID: String
        switch (definition.kind, nextTier) {
        case (.extractor, 2): researchID = "extraction_2"
        case (.extractor, 3): researchID = "extraction_3"
        case (.generator, 2): researchID = "power_2"
        case (.generator, 3): researchID = "power_3"
        default:
            return false
        }
        guard store.unlockedResearchIDs.contains(researchID) else {
            latestMessage = "Requires \(FactoryResearchCatalog.byID[researchID]?.name ?? "research")."
            return false
        }
        guard structure.tier < 3, isPlayerNear(tileID: tileID),
              consumeConstructionItem(definition.kitItemID, near: tileID) else {
            latestMessage = "Stand nearby with another \(definition.name) kit."
            return false
        }
        structure.tier = nextTier
        store.update { $0.structures[tileID] = structure }
        latestMessage = "\(definition.name) upgraded."
        return true
    }

    @discardableResult
    func demolish(at tileID: String) -> Bool {
        guard let structure = store.structures[tileID],
              let definition = FactoryCatalog.byID[structure.definitionID],
              isPlayerNear(tileID: tileID) else {
            latestMessage = "Stand on or beside the structure to dismantle it."
            return false
        }
        guard structure.inputBuffer.isEmpty, structure.outputBuffer.isEmpty else {
            latestMessage = "Empty this structure before dismantling it."
            return false
        }
        store.update { $0.structures[tileID] = nil }
        inventoryStore.deposit(constructionEngine.demolitionRefund(for: definition))
        latestMessage = "Dismantled \(definition.name)."
        return true
    }

    @discardableResult
    func unlockResearch(_ researchID: String) -> Bool {
        guard let research = FactoryResearchCatalog.byID[researchID],
              !store.unlockedResearchIDs.contains(researchID),
              research.prerequisiteIDs.isSubset(of: store.unlockedResearchIDs),
              explorerLevel >= research.explorerLevel else {
            latestMessage = "Research requirements are not yet met."
            return false
        }
        let cost = effectiveInsightCost(for: research)
        guard totalAvailableItem("atlas_insight") >= cost else {
            latestMessage = "Research requirements are not yet met."
            return false
        }
        if cost > 0 {
            guard consumeGlobalItem("atlas_insight", quantity: cost) else { return false }
        }
        store.update { $0.unlockedResearchIDs.insert(researchID) }
        latestMessage = "\(research.name) researched."
        return true
    }

    func withdraw(
        itemID: String,
        quantity: Int,
        from tileID: String,
        inputBuffer: Bool = false,
        now: Date = .now
    ) -> Bool {
        guard quantity > 0, isPlayerNear(tileID: tileID, now: now),
              var structure = store.structures[tileID] else { return false }
        let available = inputBuffer
            ? structure.inputBuffer[itemID] ?? 0
            : structure.outputBuffer[itemID] ?? 0
        guard available >= quantity else { return false }
        if inputBuffer {
            structure.inputBuffer[itemID, default: 0] -= quantity
            if structure.inputBuffer[itemID] == 0 { structure.inputBuffer[itemID] = nil }
        } else {
            structure.outputBuffer[itemID, default: 0] -= quantity
            if structure.outputBuffer[itemID] == 0 { structure.outputBuffer[itemID] = nil }
        }
        store.update { $0.structures[tileID] = structure }
        inventoryStore.deposit([ItemAmount(itemID: itemID, quantity: quantity)])
        return true
    }

    /// Pulls all depot output buffers into the backpack without requiring proximity.
    @discardableResult
    func remoteCollectAllDepots() -> Int {
        advance()
        var collected = 0
        var shipped: [ItemAmount] = []
        store.update { state in
            for (tileID, structure) in state.structures {
                guard let definition = FactoryCatalog.byID[structure.definitionID],
                      definition.kind == .depot,
                      !structure.outputBuffer.isEmpty else { continue }
                var next = structure
                for (itemID, quantity) in structure.outputBuffer where quantity > 0 {
                    shipped.append(ItemAmount(itemID: itemID, quantity: quantity))
                    collected += quantity
                }
                next.outputBuffer = [:]
                state.structures[tileID] = next
            }
        }
        if !shipped.isEmpty {
            inventoryStore.deposit(shipped)
            latestMessage = collected == 1
                ? "Collected 1 item from remote depots."
                : "Collected \(collected) items from remote depots."
        } else {
            latestMessage = "No depot stock ready to collect."
        }
        return collected
    }

    var remoteCollectableItemCount: Int {
        store.structures.values.reduce(0) { partial, structure in
            guard let definition = FactoryCatalog.byID[structure.definitionID],
                  definition.kind == .depot else { return partial }
            return partial + structure.outputBuffer.values.reduce(0, +)
        }
    }

    func deposit(
        itemID: String,
        quantity: Int,
        into tileID: String,
        now: Date = .now
    ) -> Bool {
        guard quantity > 0, isPlayerNear(tileID: tileID, now: now),
              var structure = store.structures[tileID],
              let definition = FactoryCatalog.byID[structure.definitionID],
              canManuallyLoad(itemID: itemID, into: definition),
              inventoryStore.consume([ItemAmount(itemID: itemID, quantity: quantity)]) else { return false }
        if definition.kind == .depot {
            guard structure.outputBuffer.values.reduce(0, +) + quantity <= definition.storageCapacity else {
                inventoryStore.deposit([ItemAmount(itemID: itemID, quantity: quantity)])
                return false
            }
            structure.outputBuffer[itemID, default: 0] += quantity
        } else {
            guard structure.inputBuffer.values.reduce(0, +) + quantity <= FactorySimulationEngine.defaultBufferCapacity else {
                inventoryStore.deposit([ItemAmount(itemID: itemID, quantity: quantity)])
                return false
            }
            structure.inputBuffer[itemID, default: 0] += quantity
        }
        store.update { $0.structures[tileID] = structure }
        return true
    }

    func canManuallyLoad(itemID: String, into definition: FactoryStructureDefinition) -> Bool {
        switch definition.kind {
        case .depot:
            return true
        case .generator:
            return itemID == "amber_resin"
        case .processor, .research:
            return definition.allowedRecipeIDs
                .compactMap { FactoryRecipeCatalog.byID[$0] }
                .flatMap(\.inputs)
                .contains { $0.itemID == itemID }
        case .road, .extractor:
            return false
        }
    }

    func clearFactory(at date: Date = .now) {
        store.clear(at: date)
        isBuildModeActive = false
        selectedBuildDefinitionID = nil
        selectedStructureID = nil
    }

    private func isPlayerNear(tileID: String, now: Date = .now) -> Bool {
        guard let location = playerLocation,
              now.timeIntervalSince(location.timestamp) >= 0,
              now.timeIntervalSince(location.timestamp) <= ConstructionEngine.maximumLocationAge,
              let target = tileStore.tileEngine.parseTileID(tileID) else { return false }
        let player = tileStore.tileEngine.axialCoordinate(for: location.coordinate)
        return TileEngine.hexDistance(player, target) <= 1
    }

    private func validateRoadUpgrade(
        existing: FactoryStructureDefinition,
        replacement: FactoryStructureDefinition,
        tileID: String,
        now: Date
    ) -> ConstructionValidation {
        guard let oldTier = existing.roadTier, let newTier = replacement.roadTier,
              newTier.rawValue == oldTier.rawValue + 1 else {
            return .denied("Roads must be upgraded one tier at a time.")
        }
        guard replacement.requiredResearchID.map(store.unlockedResearchIDs.contains) ?? true else {
            return .denied("Required logistics research is locked.")
        }
        guard isPlayerNear(tileID: tileID, now: now) else {
            return .denied("Stand on or beside this road to upgrade it.")
        }
        guard availableConstructionItemCount(replacement.kitItemID, near: tileID) > 0 else {
            return .denied("The required road kit is not available.")
        }
        return .allowed("Ready to upgrade \(existing.name).")
    }

    private func applyRoadUpgrade(_ definition: FactoryStructureDefinition, at tileID: String) -> Bool {
        guard consumeConstructionItem(definition.kitItemID, near: tileID),
              var structure = store.structures[tileID] else { return false }
        structure.definitionID = definition.id
        structure.tier = definition.roadTier?.rawValue ?? structure.tier
        store.update { $0.structures[tileID] = structure }
        latestMessage = "Upgraded to \(definition.name)."
        return true
    }

    private func networkAdjacent(to tileID: String) -> FactoryNetworkSnapshot? {
        guard let target = tileStore.tileEngine.parseTileID(tileID) else { return nil }
        let adjacent = Set(tileStore.tileEngine.neighbors(of: target).map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: tileStore.tileEngine.tileSizeMeters)
        })
        return networks.first { !$0.roadTileIDs.isDisjoint(with: adjacent) }
    }

    private func availableConstructionItemCount(_ itemID: String, near tileID: String) -> Int {
        var total = inventoryStore.quantity(of: itemID)
        guard store.unlockedResearchIDs.contains("logistics_1"),
              let network = networkAdjacent(to: tileID) else { return total }
        for depotID in network.buildingTileIDs {
            guard let structure = store.structures[depotID],
                  FactoryCatalog.byID[structure.definitionID]?.kind == .depot else { continue }
            total += structure.outputBuffer[itemID] ?? 0
        }
        return total
    }

    private func consumeConstructionItem(_ itemID: String, near tileID: String) -> Bool {
        if inventoryStore.quantity(of: itemID) > 0 {
            return inventoryStore.consume([ItemAmount(itemID: itemID, quantity: 1)])
        }
        guard store.unlockedResearchIDs.contains("logistics_1"),
              let network = networkAdjacent(to: tileID) else { return false }
        for depotID in network.buildingTileIDs.sorted() {
            guard var depot = store.structures[depotID],
                  FactoryCatalog.byID[depot.definitionID]?.kind == .depot,
                  (depot.outputBuffer[itemID] ?? 0) > 0 else { continue }
            depot.outputBuffer[itemID, default: 0] -= 1
            if depot.outputBuffer[itemID] == 0 { depot.outputBuffer[itemID] = nil }
            store.update { $0.structures[depotID] = depot }
            return true
        }
        return false
    }

    private func totalAvailableItem(_ itemID: String) -> Int {
        inventoryStore.quantity(of: itemID) + structures.reduce(0) { total, structure in
            guard FactoryCatalog.byID[structure.definitionID]?.kind == .depot else { return total }
            return total + (structure.outputBuffer[itemID] ?? 0)
        }
    }

    private func consumeGlobalItem(_ itemID: String, quantity: Int) -> Bool {
        guard totalAvailableItem(itemID) >= quantity else { return false }
        var remaining = quantity
        let backpack = min(remaining, inventoryStore.quantity(of: itemID))
        if backpack > 0 {
            _ = inventoryStore.consume([ItemAmount(itemID: itemID, quantity: backpack)])
            remaining -= backpack
        }
        for depotID in structures.map(\.tileID).sorted() where remaining > 0 {
            guard var depot = store.structures[depotID],
                  FactoryCatalog.byID[depot.definitionID]?.kind == .depot else { continue }
            let taken = min(remaining, depot.outputBuffer[itemID] ?? 0)
            guard taken > 0 else { continue }
            depot.outputBuffer[itemID, default: 0] -= taken
            if depot.outputBuffer[itemID] == 0 { depot.outputBuffer[itemID] = nil }
            store.update { $0.structures[depotID] = depot }
            remaining -= taken
        }
        return remaining == 0
    }
}
