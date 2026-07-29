import Foundation

struct ConstructionValidation: Sendable, Equatable {
    let isAllowed: Bool
    let message: String

    static func allowed(_ message: String = "Ready to build") -> ConstructionValidation {
        ConstructionValidation(isAllowed: true, message: message)
    }

    static func denied(_ message: String) -> ConstructionValidation {
        ConstructionValidation(isAllowed: false, message: message)
    }
}

struct ConstructionEngine: Sendable {
    static let maximumLocationAge: TimeInterval = 120

    func deposit(for tileID: String) -> FactoryDeposit {
        let seed = StableHash.fnv1a64("factory-deposit:\(tileID)")
        let roll = Int(seed % 100)
        let kind: FactoryDepositKind
        switch roll {
        case 0..<30: kind = .cobble
        case 30..<55: kind = .moss
        case 55..<70: kind = .copper
        case 70..<80: kind = .amber
        case 80..<90: kind = .waystone
        default: kind = .empty
        }
        let capacity = kind == .empty ? 0 : 300 + Int((seed / 101) % 301)
        return FactoryDeposit(kind: kind, capacity: capacity)
    }

    func validatePlacement(
        definition: FactoryStructureDefinition,
        targetTile: WorldTile?,
        playerTile: TileCoordinate?,
        locationTimestamp: Date?,
        now: Date,
        structures: [String: PlacedFactoryStructure],
        unlockedResearchIDs: Set<String>,
        availableKitCount: Int,
        tileEngine: TileEngine
    ) -> ConstructionValidation {
        guard let locationTimestamp, now.timeIntervalSince(locationTimestamp) >= 0,
              now.timeIntervalSince(locationTimestamp) <= Self.maximumLocationAge,
              let playerTile else {
            return .denied("Move nearby to establish your current atlas hex.")
        }
        guard let targetTile, targetTile.isDiscovered else {
            return .denied("Discover this tile before building.")
        }
        guard TileEngine.hexDistance(playerTile, targetTile.coordinate) <= 1 else {
            return .denied("Stand on this tile or an adjacent tile.")
        }
        guard structures[targetTile.id] == nil else {
            return .denied("This hex already contains a structure.")
        }
        if let research = definition.requiredResearchID,
           !unlockedResearchIDs.contains(research) {
            return .denied("Requires \(FactoryResearchCatalog.byID[research]?.name ?? "more research").")
        }
        guard availableKitCount > 0 else {
            return .denied("Craft a \(ItemCatalog.definition(for: definition.kitItemID)?.name ?? "construction kit") first.")
        }
        if definition.kind == .extractor {
            guard targetTile.state.rawValue >= TileState.explored.rawValue else {
                return .denied("Revisit this tile until it is explored to reveal its deposit.")
            }
            guard deposit(for: targetTile.id).kind != .empty else {
                return .denied("This tile has no extractable deposit.")
            }
        }
        _ = tileEngine
        return .allowed()
    }

    func demolitionRefund(for definition: FactoryStructureDefinition) -> [ItemAmount] {
        if definition.kind == .road {
            return [ItemAmount(itemID: "cobble_chip", quantity: 1)]
        }
        guard let recipe = ItemRecipes.all.first(where: { $0.primaryOutput?.itemID == definition.kitItemID }) else {
            return []
        }
        return recipe.inputs.compactMap { input in
            let quantity = input.quantity / 2
            return quantity > 0 ? ItemAmount(itemID: input.itemID, quantity: quantity) : nil
        }
    }
}

