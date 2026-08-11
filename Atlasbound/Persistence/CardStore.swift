import Foundation
import Combine

/// Owns the local card collection and training encounter snapshot. Competitive copies
/// are later mirrored to the server ledger; this store remains the offline cache.
@MainActor
final class CardStore: ObservableObject {
    @Published private(set) var state: CardState
    @Published private(set) var latestMessage: String?

    private let database: AtlasDatabase
    private let battleEngine = CrewfrontBattleEngine()

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil, now: Date = .now) {
        if let database { self.database = database }
        else if let fileURL { self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL)) }
        else { self.database = .shared }
        if let loaded = self.database.loadCardState() { state = loaded }
        else { state = .empty(now: now); persist() }
    }

    var blueprints: [CardBlueprint] {
        state.knownBlueprintIDs.compactMap { CrewfrontCatalog.byID[$0] }.sorted { $0.name < $1.name }
    }
    var instances: [CardInstance] { state.instances }
    var decks: [BattleDeck] { state.decks }
    var activeBattle: BattleState? { state.activeBattle }
    var activeDeck: BattleDeck? { state.decks.first }

    func quantity(of blueprintID: String) -> Int { state.instances.filter { $0.blueprintID == blueprintID }.count }

    @discardableResult
    func craft(blueprintID: String, inventory: InventoryStore, now: Date = .now) -> CardInstance? {
        guard state.knownBlueprintIDs.contains(blueprintID),
              let blueprint = CrewfrontCatalog.byID[blueprintID],
              inventory.consume(blueprint.craftInputs) else {
            latestMessage = "Gather the listed materials before crafting this card."
            return nil
        }
        let card = CardInstance(id: UUID(), blueprintID: blueprintID, integrity: .ready, isProtected: false, craftedAt: now)
        state.instances.append(card)
        persist()
        latestMessage = "Crafted \(blueprint.name)."
        return card
    }

    func repair(instanceID: UUID, inventory: InventoryStore) {
        guard let index = state.instances.firstIndex(where: { $0.id == instanceID }),
              state.instances[index].integrity != .ready,
              inventory.consume([.init(itemID: "brass_rivet", quantity: 1), .init(itemID: "moss_scrap", quantity: 1)]) else {
            latestMessage = "Repair needs one Brass Rivet and one Moss Scrap."
            return
        }
        state.instances[index].integrity = .ready
        persist()
        latestMessage = "Card repaired."
    }

    func updateDeck(_ deck: BattleDeck) {
        guard battleEngine.validate(deck: deck, instances: state.instances) == nil,
              let index = state.decks.firstIndex(where: { $0.id == deck.id }) else { return }
        state.decks[index] = deck
        persist()
    }

    func equipMostRecent(blueprintID: String) {
        guard let deckIndex = state.decks.indices.first,
              let instance = state.instances.last(where: { $0.blueprintID == blueprintID }),
              !state.decks[deckIndex].cardInstanceIDs.contains(instance.id) else {
            latestMessage = "Craft another copy before adding it to this deck."
            return
        }
        let duplicateCount = state.decks[deckIndex].cardInstanceIDs.reduce(0) { total, id in
            total + (state.instances.first(where: { $0.id == id })?.blueprintID == blueprintID ? 1 : 0)
        }
        guard duplicateCount < 2 else {
            latestMessage = "A field deck can use at most two copies of a blueprint."
            return
        }
        state.decks[deckIndex].cardInstanceIDs.removeLast()
        state.decks[deckIndex].cardInstanceIDs.append(instance.id)
        state.decks[deckIndex].updatedAt = .now
        persist()
        latestMessage = "Added \(CrewfrontCatalog.byID[blueprintID]?.name ?? "card") to Field Deck."
    }

    func startTraining(now: Date = .now) {
        guard let deck = activeDeck else { return }
        guard let battle = battleEngine.startTraining(deck: deck, instances: state.instances, now: now) else {
            latestMessage = battleEngine.validate(deck: deck, instances: state.instances)
            return
        }
        state.activeBattle = battle
        persist()
    }

    func resolveTraining(action: PlannedBattleAction, now: Date = .now) {
        guard let battle = state.activeBattle else { return }
        let aiActions = battle.participants.filter(\.isAI).compactMap { participant -> PlannedBattleAction? in
            guard let card = participant.hand.first else { return nil }
            return PlannedBattleAction(id: UUID(), participantID: participant.id, kind: .deploy, cardInstanceID: card, targetHex: .center, submittedAt: now)
        }
        state.activeBattle = battleEngine.resolve(state: battle, actions: [action] + aiActions, instances: state.instances, now: now)
        persist()
    }

    func playCard(instanceID: UUID, participantID: UUID, targetHex: BattleHex = .center, now: Date = .now) {
        guard let instance = state.instances.first(where: { $0.id == instanceID }), let card = CrewfrontCatalog.byID[instance.blueprintID] else { return }
        resolveTraining(action: PlannedBattleAction(id: UUID(), participantID: participantID, kind: card.kind == .tactic ? .reinforce : .deploy, cardInstanceID: instanceID, targetHex: targetHex, submittedAt: now), now: now)
    }

    func abandonTraining() { state.activeBattle = nil; persist() }
    func resetLocalSession() { state = .empty(); latestMessage = nil; persist() }

    private func persist() { database.saveCardState(state) }
    private static func sqliteURL(from url: URL) -> URL { url.pathExtension.lowercased() == "json" ? url.deletingPathExtension().appendingPathExtension("sqlite") : url }
}

#if DEBUG
extension CardStore {
    func debugUnlockAll(now: Date = .now) {
        state.knownBlueprintIDs = Set(CrewfrontCatalog.blueprints.map(\.id))
        for blueprint in CrewfrontCatalog.blueprints where state.instances.filter({ $0.blueprintID == blueprint.id }).count < 2 {
            state.instances.append(CardInstance(id: UUID(), blueprintID: blueprint.id, integrity: .ready, isProtected: false, craftedAt: now))
        }
        persist()
        latestMessage = "All Crewfront blueprints and craft copies unlocked."
    }
}
#endif
