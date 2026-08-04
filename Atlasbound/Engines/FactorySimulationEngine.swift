import Foundation

struct FactorySimulationEngine: Sendable {
    static let maximumOfflineMinutes = 8 * 60
    static let defaultBufferCapacity = 20

    private let networkEngine = FactoryNetworkEngine()
    private let constructionEngine = ConstructionEngine()

    func advance(
        state initialState: FactoryState,
        to date: Date,
        tileEngine: TileEngine,
        speedMultiplier: Double = 1
    ) -> FactoryState {
        var state = initialState
        let elapsed = date.timeIntervalSince(state.lastSimulatedAt)
        guard elapsed >= 0 else {
            state.lastSimulatedAt = date
            return state
        }
        let totalMinutes = Int(elapsed / 60)
        guard totalMinutes > 0 else { return state }
        let minutes = min(totalMinutes, Self.maximumOfflineMinutes)
        // Topology cannot change during a pure advance, so derive it once even for
        // the maximum 480-minute offline window.
        let networks = networkEngine.networks(
            structures: state.structures,
            tileEngine: tileEngine
        )
        let paths = cachedDepotPaths(
            networks: networks,
            structures: state.structures,
            tileEngine: tileEngine
        )
        let speed = max(1, speedMultiplier)
        for _ in 0..<minutes {
            simulateMinute(
                state: &state,
                networks: networks,
                cachedPaths: paths,
                tileEngine: tileEngine,
                speedMultiplier: speed
            )
        }
        state.lastSimulatedAt = totalMinutes > Self.maximumOfflineMinutes
            ? date
            : state.lastSimulatedAt.addingTimeInterval(TimeInterval(minutes * 60))
        return state
    }

    private func simulateMinute(
        state: inout FactoryState,
        networks: [FactoryNetworkSnapshot],
        cachedPaths: [String: [String]],
        tileEngine: TileEngine,
        speedMultiplier: Double
    ) {
        for network in networks {
            simulate(
                network: network,
                state: &state,
                cachedPaths: cachedPaths,
                tileEngine: tileEngine,
                speedMultiplier: speedMultiplier
            )
        }
    }

    private func simulate(
        network: FactoryNetworkSnapshot,
        state: inout FactoryState,
        cachedPaths: [String: [String]],
        tileEngine: TileEngine,
        speedMultiplier: Double
    ) {
        var remainingRoadCapacity = Dictionary(uniqueKeysWithValues: network.roadTileIDs.map { roadID in
            let tier = state.structures[roadID]
                .flatMap { FactoryCatalog.byID[$0.definitionID]?.roadTier } ?? .trail
            var capacity = tier.capacityPerMinute
            if state.unlockedResearchIDs.contains("logistics_3") {
                capacity = Int((Double(capacity) * 1.25).rounded())
            }
            return (roadID, capacity)
        })

        let buildingIDs = network.buildingTileIDs.sorted()
        let depotIDs = buildingIDs.filter {
            state.structures[$0].flatMap { FactoryCatalog.byID[$0.definitionID] }?.kind == .depot
        }
        let generatorIDs = buildingIDs.filter {
            state.structures[$0].flatMap { FactoryCatalog.byID[$0.definitionID] }?.kind == .generator
        }

        var availablePower = 0
        for id in generatorIDs {
            guard var generator = state.structures[id],
                  let definition = FactoryCatalog.byID[generator.definitionID] else { continue }
            if generator.fueledMinutes <= 0 {
                _ = pull(
                    itemID: "amber_resin",
                    quantity: 1,
                    into: &generator,
                    fromDepots: depotIDs,
                    state: &state,
                    network: network,
                    cachedPaths: cachedPaths,
                    remainingRoadCapacity: &remainingRoadCapacity,
                    tileEngine: tileEngine
                )
                if (generator.inputBuffer["amber_resin"] ?? 0) > 0 {
                    generator.inputBuffer["amber_resin", default: 0] -= 1
                    generator.fueledMinutes = 10
                }
            }
            if generator.fueledMinutes > 0 {
                if generator.tier >= 3 {
                    availablePower += 80
                } else if generator.tier >= 2 {
                    availablePower += 50
                } else {
                    availablePower += definition.powerSupply
                }
            }
            state.structures[id] = generator
        }

        let consumers = buildingIDs.compactMap { id -> (String, FactoryPriority, Int)? in
            guard let structure = state.structures[id],
                  let definition = FactoryCatalog.byID[structure.definitionID],
                  definition.powerDemand > 0 else { return nil }
            return (id, structure.priority, definition.powerDemand)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0 < $1.0
        }

        var powered: Set<String> = []
        for consumer in consumers where availablePower >= consumer.2 {
            availablePower -= consumer.2
            powered.insert(consumer.0)
        }
        if !powered.isEmpty {
            for id in generatorIDs {
                guard var generator = state.structures[id], generator.fueledMinutes > 0 else { continue }
                generator.fueledMinutes -= 1
                state.structures[id] = generator
            }
        }

        for id in consumers.map(\.0) where powered.contains(id) {
            guard var structure = state.structures[id],
                  let definition = FactoryCatalog.byID[structure.definitionID] else { continue }

            switch definition.kind {
            case .extractor:
                let deposit = constructionEngine.deposit(for: id)
                if let itemID = deposit.kind.outputItemID, structure.extractedUnits < deposit.capacity {
                    var amount = 1
                    if state.unlockedResearchIDs.contains("extraction_3") && structure.tier >= 3 {
                        amount = 3
                    } else if state.unlockedResearchIDs.contains("extraction_2") && structure.tier >= 2 {
                        amount = 2
                    }
                    // Soft Artifice speed occasionally yields an extra unit.
                    if speedMultiplier > 1.25, StableHash.fnv1a64("extract:\(id):\(structure.extractedUnits)") % 4 == 0 {
                        amount += 1
                    }
                    let remaining = deposit.capacity - structure.extractedUnits
                    let produced = min(amount, remaining)
                    if totalQuantity(structure.outputBuffer) + produced <= Self.defaultBufferCapacity {
                        structure.outputBuffer[itemID, default: 0] += produced
                        structure.extractedUnits += produced
                        state.lifetimeProduced[itemID, default: 0] += produced
                    }
                }
            case .processor, .research:
                guard let recipeID = structure.selectedRecipeID,
                      let recipe = FactoryRecipeCatalog.byID[recipeID],
                      definition.allowedRecipeIDs.contains(recipeID),
                      recipe.requiredResearchID.map(state.unlockedResearchIDs.contains) ?? true else {
                    state.structures[id] = structure
                    continue
                }
                for input in recipe.inputs {
                    let missing = max(0, input.quantity - (structure.inputBuffer[input.itemID] ?? 0))
                    if missing > 0 {
                        _ = pull(
                            itemID: input.itemID,
                            quantity: missing,
                            into: &structure,
                            fromDepots: depotIDs,
                            state: &state,
                            network: network,
                            cachedPaths: cachedPaths,
                            remainingRoadCapacity: &remainingRoadCapacity,
                            tileEngine: tileEngine
                        )
                    }
                }
                if has(recipe.inputs, in: structure.inputBuffer),
                   canFit(recipe.outputs, in: structure.outputBuffer, capacity: Self.defaultBufferCapacity) {
                    structure.recipeProgressMinutes += 1
                    let durationBonus = state.unlockedResearchIDs.contains("automation_2") ? 1.1 : 1.0
                    let effectiveDuration = max(
                        1,
                        Int((Double(recipe.durationMinutes) / (speedMultiplier * durationBonus)).rounded())
                    )
                    if structure.recipeProgressMinutes >= effectiveDuration {
                        subtract(recipe.inputs, from: &structure.inputBuffer)
                        add(recipe.outputs, to: &structure.outputBuffer)
                        for output in recipe.outputs {
                            state.lifetimeProduced[output.itemID, default: 0] += output.quantity
                        }
                        structure.recipeProgressMinutes = 0
                    }
                }
            case .road, .depot, .generator:
                break
            }
            state.structures[id] = structure
            flushOutputs(
                fromID: id,
                toDepots: depotIDs,
                state: &state,
                network: network,
                cachedPaths: cachedPaths,
                remainingRoadCapacity: &remainingRoadCapacity,
                tileEngine: tileEngine
            )
        }
    }

    private func pull(
        itemID: String,
        quantity: Int,
        into structure: inout PlacedFactoryStructure,
        fromDepots depotIDs: [String],
        state: inout FactoryState,
        network: FactoryNetworkSnapshot,
        cachedPaths: [String: [String]],
        remainingRoadCapacity: inout [String: Int],
        tileEngine: TileEngine
    ) -> Int {
        var moved = 0
        let candidates = depotIDs.compactMap { depotID -> (String, [String])? in
            guard (state.structures[depotID]?.outputBuffer[itemID] ?? 0) > 0,
                  let path = cachedPaths[routeKey(depotID, structure.tileID)] else { return nil }
            return (depotID, path)
        }.sorted {
            $0.1.count == $1.1.count ? $0.0 < $1.0 : $0.1.count < $1.1.count
        }
        for candidate in candidates where moved < quantity {
            let capacity = candidate.1.map { remainingRoadCapacity[$0] ?? 0 }.min() ?? 0
            guard capacity > 0, var depot = state.structures[candidate.0] else { continue }
            let available = depot.outputBuffer[itemID] ?? 0
            let amount = min(quantity - moved, available, capacity)
            guard amount > 0 else { continue }
            depot.outputBuffer[itemID, default: 0] -= amount
            if depot.outputBuffer[itemID] == 0 { depot.outputBuffer[itemID] = nil }
            structure.inputBuffer[itemID, default: 0] += amount
            for roadID in candidate.1 {
                remainingRoadCapacity[roadID, default: 0] -= amount
            }
            state.structures[candidate.0] = depot
            moved += amount
        }
        return moved
    }

    private func flushOutputs(
        fromID: String,
        toDepots depotIDs: [String],
        state: inout FactoryState,
        network: FactoryNetworkSnapshot,
        cachedPaths: [String: [String]],
        remainingRoadCapacity: inout [String: Int],
        tileEngine: TileEngine
    ) {
        guard var source = state.structures[fromID], !source.outputBuffer.isEmpty else { return }
        let candidates = depotIDs.filter { $0 != fromID }.compactMap { depotID -> (String, [String])? in
            guard let depot = state.structures[depotID],
                  let definition = FactoryCatalog.byID[depot.definitionID],
                  totalQuantity(depot.outputBuffer) < definition.storageCapacity,
                  let path = cachedPaths[routeKey(fromID, depotID)] else { return nil }
            return (depotID, path)
        }.sorted {
            $0.1.count == $1.1.count ? $0.0 < $1.0 : $0.1.count < $1.1.count
        }

        for itemID in source.outputBuffer.keys.sorted() {
            for candidate in candidates {
                guard var depot = state.structures[candidate.0],
                      let definition = FactoryCatalog.byID[depot.definitionID] else { continue }
                let freeStorage = definition.storageCapacity - totalQuantity(depot.outputBuffer)
                let pathCapacity = candidate.1.map { remainingRoadCapacity[$0] ?? 0 }.min() ?? 0
                let amount = min(source.outputBuffer[itemID] ?? 0, freeStorage, pathCapacity)
                guard amount > 0 else { continue }
                source.outputBuffer[itemID, default: 0] -= amount
                depot.outputBuffer[itemID, default: 0] += amount
                for roadID in candidate.1 {
                    remainingRoadCapacity[roadID, default: 0] -= amount
                }
                state.structures[candidate.0] = depot
                if source.outputBuffer[itemID] == 0 { source.outputBuffer[itemID] = nil }
                if source.outputBuffer[itemID] == nil { break }
            }
        }
        state.structures[fromID] = source
    }

    private func totalQuantity(_ buffer: [String: Int]) -> Int {
        buffer.values.reduce(0, +)
    }

    private func has(_ amounts: [ItemAmount], in buffer: [String: Int]) -> Bool {
        amounts.allSatisfy { (buffer[$0.itemID] ?? 0) >= $0.quantity }
    }

    private func canFit(_ amounts: [ItemAmount], in buffer: [String: Int], capacity: Int) -> Bool {
        totalQuantity(buffer) + amounts.reduce(0) { $0 + $1.quantity } <= capacity
    }

    private func subtract(_ amounts: [ItemAmount], from buffer: inout [String: Int]) {
        for amount in amounts {
            buffer[amount.itemID, default: 0] -= amount.quantity
            if buffer[amount.itemID] == 0 { buffer[amount.itemID] = nil }
        }
    }

    private func add(_ amounts: [ItemAmount], to buffer: inout [String: Int]) {
        for amount in amounts {
            buffer[amount.itemID, default: 0] += amount.quantity
        }
    }

    private func cachedDepotPaths(
        networks: [FactoryNetworkSnapshot],
        structures: [String: PlacedFactoryStructure],
        tileEngine: TileEngine
    ) -> [String: [String]] {
        var output: [String: [String]] = [:]
        for network in networks {
            let depots = network.buildingTileIDs.filter {
                structures[$0].flatMap { FactoryCatalog.byID[$0.definitionID] }?.kind == .depot
            }
            for depotID in depots {
                for buildingID in network.buildingTileIDs where buildingID != depotID {
                    guard let path = networkEngine.shortestRoadPath(
                        fromBuildingID: depotID,
                        toBuildingID: buildingID,
                        network: network,
                        tileEngine: tileEngine
                    ) else { continue }
                    output[routeKey(depotID, buildingID)] = path
                    output[routeKey(buildingID, depotID)] = path.reversed()
                }
            }
        }
        return output
    }

    private func routeKey(_ from: String, _ to: String) -> String {
        "\(from)→\(to)"
    }
}
