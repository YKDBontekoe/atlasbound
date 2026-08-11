import Foundation

/// Deterministic rules for local training and server conformance fixtures.
struct CrewfrontBattleEngine: Sendable {
    func validate(deck: BattleDeck, instances: [CardInstance]) -> String? {
        guard deck.cardInstanceIDs.count == 12 else { return "A field deck needs exactly 12 cards." }
        let available = Set(instances.map(\.id))
        guard Set(deck.cardInstanceIDs).count == deck.cardInstanceIDs.count,
              deck.cardInstanceIDs.allSatisfy(available.contains) else { return "That deck contains an unavailable card." }
        let grouped = Dictionary(grouping: deck.cardInstanceIDs) { id in instances.first { $0.id == id }?.blueprintID ?? "" }
        guard grouped.values.allSatisfy({ $0.count <= 2 }) else { return "A deck can use at most two copies of a blueprint." }
        return nil
    }

    func startTraining(deck: BattleDeck, instances: [CardInstance], now: Date = .now) -> BattleState? {
        guard validate(deck: deck, instances: instances) == nil else { return nil }
        let shuffled = deck.cardInstanceIDs.sorted { StableHash.fnv1a64("\($0.uuidString):\(deck.id.uuidString)") < StableHash.fnv1a64("\($1.uuidString):\(deck.id.uuidString)") }
        let player = BattleParticipant(id: UUID(), team: .dawn, displayName: "You", deckID: deck.id, hand: Array(shuffled.prefix(4)), drawPile: Array(shuffled.dropFirst(4)), energy: 3, isAI: false)
        let aiDeck = BattleDeck(id: UUID(), name: "Guardian", cardInstanceIDs: shuffled, relicID: nil, updatedAt: now)
        let guardian = BattleParticipant(id: UUID(), team: .dusk, displayName: "Atlas Guardian", deckID: aiDeck.id, hand: Array(shuffled.prefix(4)), drawPile: Array(shuffled.dropFirst(4)), energy: 3, isAI: true)
        return BattleState(id: UUID(), round: 1, dawnInfluence: 0, duskInfluence: 0, guardianDurability: 8, pieces: [], participants: [player, guardian], events: [BattleEvent(id: UUID(), round: 1, title: "Guardian detected", detail: "Control the Beacon or break the Guardian’s hold.", createdAt: now)], winner: nil, seededTieBreak: Int(StableHash.fnv1a64(deck.id.uuidString) % 2))
    }

    func resolve(state: BattleState, actions: [PlannedBattleAction], instances: [CardInstance], now: Date = .now) -> BattleState {
        guard state.winner == nil else { return state }
        var next = state
        let instanceByID = Dictionary(uniqueKeysWithValues: instances.map { ($0.id, $0) })
        let ordered = actions.sorted {
            let left = $0.cardInstanceID.flatMap { instanceByID[$0] }.flatMap { CrewfrontCatalog.byID[$0.blueprintID] }?.speed ?? 0
            let right = $1.cardInstanceID.flatMap { instanceByID[$0] }.flatMap { CrewfrontCatalog.byID[$0.blueprintID] }?.speed ?? 0
            return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
        }
        for action in ordered {
            guard let index = next.participants.firstIndex(where: { $0.id == action.participantID }),
                  let instanceID = action.cardInstanceID,
                  let instance = instanceByID[instanceID],
                  let blueprint = CrewfrontCatalog.byID[instance.blueprintID],
                  next.participants[index].hand.contains(instanceID),
                  next.participants[index].energy >= blueprint.energyCost
            else { continue }
            next.participants[index].energy -= blueprint.energyCost
            next.participants[index].hand.removeAll { $0 == instanceID }
            switch action.kind {
            case .deploy where blueprint.kind != .tactic:
                let hex = action.targetHex ?? .center
                if !next.pieces.contains(where: { $0.hex == hex }) {
                    next.pieces.append(BoardPiece(id: UUID(), cardInstanceID: instanceID, team: next.participants[index].team, hex: hex, remainingDurability: max(1, blueprint.durability)))
                    next.events.append(event(next, "\(blueprint.name) deployed", "The field changes around \(hex == .center ? "the Beacon" : "the outer ring").", now))
                }
            case .reinforce, .deploy:
                applyTactic(blueprint, team: next.participants[index].team, into: &next, now: now)
            case .pass:
                break
            }
        }
        scoreRound(&next, now: now)
        return next
    }

    private func applyTactic(_ blueprint: CardBlueprint, team: BattleTeam, into state: inout BattleState, now: Date) {
        let power = max(1, blueprint.power)
        if blueprint.id == "field_repair", let index = state.pieces.indices.first(where: { state.pieces[$0].team == team }) {
            state.pieces[index].remainingDurability += power
        } else if blueprint.id == "atlas_pulse" || blueprint.id == "artificer_spark" {
            state.guardianDurability = max(0, state.guardianDurability - power)
        } else if team == .dawn {
            state.dawnInfluence += 1
        } else {
            state.duskInfluence += 1
        }
        state.events.append(event(state, blueprint.name, "Its effect ripples through the encounter.", now))
    }

    private func scoreRound(_ state: inout BattleState, now: Date) {
        let dawnCenter = state.pieces.contains { $0.team == .dawn && $0.hex == .center }
        let duskCenter = state.pieces.contains { $0.team == .dusk && $0.hex == .center }
        if dawnCenter != duskCenter {
            if dawnCenter { state.dawnInfluence += 1 }
            else { state.duskInfluence += 1 }
        }
        if state.guardianDurability == 0 { state.dawnInfluence += 2 }
        if state.dawnInfluence >= BattleState.victoryInfluence || state.duskInfluence >= BattleState.victoryInfluence || state.round >= BattleState.maximumRounds {
            if state.dawnInfluence == state.duskInfluence {
                state.winner = state.seededTieBreak == 0 ? .dawn : .dusk
            } else { state.winner = state.dawnInfluence > state.duskInfluence ? .dawn : .dusk }
            state.events.append(event(state, state.winner == .dawn ? "Beacon secured" : "Guardian holds", "The training encounter is complete.", now))
            return
        }
        state.round += 1
        for index in state.participants.indices {
            state.participants[index].energy = 3
            if let card = state.participants[index].drawPile.first {
                state.participants[index].drawPile.removeFirst()
                state.participants[index].hand.append(card)
            }
        }
    }

    private func event(_ state: BattleState, _ title: String, _ detail: String, _ date: Date) -> BattleEvent {
        BattleEvent(id: UUID(), round: state.round, title: title, detail: detail, createdAt: date)
    }
}
