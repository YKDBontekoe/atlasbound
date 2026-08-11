import SwiftUI

struct DeckWorkshopView: View {
    @ObservedObject var cardStore: CardStore
    @ObservedObject var inventory: InventoryStore
    @State private var selectedBattle: BattleState?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: AtlasTheme.Space.lg) {
                StatSectionCard {
                    VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                        AtlasSectionHeader(title: "Field deck", subtitle: "Craft duplicate cards from your gathered materials, then practice at a stationary Beacon.", systemImage: "rectangle.stack.fill", accent: AtlasTheme.blue)
                        let count = cardStore.activeDeck?.cardInstanceIDs.count ?? 0
                        AtlasMetricRow(label: "Deck cards", value: "\(count)/12", systemImage: "rectangle.stack")
                        Text(count == 12 ? "Ready: start a short practice battle to learn what each card does." : "Add cards until your field deck reaches 12. Your first deck is ready to play.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Start Guardian training") {
                            cardStore.startTraining()
                            selectedBattle = cardStore.activeBattle
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AtlasTheme.blue)
                        .disabled(count != 12)
                        if let message = cardStore.latestMessage {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                StatSectionCard {
                    VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                        AtlasSectionHeader(title: "Blueprints", subtitle: "Blueprints are permanent. Crafted copies may later be repaired or staked in crew sieges.", systemImage: "square.on.square", accent: AtlasTheme.teal)
                        Text("Tip: your active deck is already equipped. Crafting gives you optional duplicate choices later.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(cardStore.blueprints) { blueprint in
                            BlueprintRow(blueprint: blueprint, copies: cardStore.quantity(of: blueprint.id), onCraft: {
                                _ = cardStore.craft(blueprintID: blueprint.id, inventory: inventory)
                            }, onEquip: {
                                cardStore.equipMostRecent(blueprintID: blueprint.id)
                            })
                            if blueprint.id != cardStore.blueprints.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(AtlasTheme.Space.xl)
        }
        .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Decks")
        .sheet(item: $selectedBattle) { battle in
            TrainingBattleView(cardStore: cardStore, battleID: battle.id) {
                selectedBattle = nil
            }
        }
    }
}

private struct BlueprintRow: View {
    let blueprint: CardBlueprint
    let copies: Int
    let onCraft: () -> Void
    let onEquip: () -> Void

    var body: some View {
        HStack(spacing: AtlasTheme.Space.md) {
            Image(systemName: blueprint.symbolName)
                .foregroundStyle(AtlasTheme.blue)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(blueprint.name).font(.subheadline.weight(.semibold))
                Text("\(blueprint.kind.displayName) · \(blueprint.energyCost) energy · \(blueprint.detail)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(blueprint.craftInputs.map { "\($0.quantity)× \(ItemCatalog.definition(for: $0.itemID)?.name ?? $0.itemID)" }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Text("×\(copies)").font(.caption.weight(.bold)).foregroundStyle(AtlasTheme.teal)
                Button("Craft", action: onCraft).buttonStyle(.bordered)
                if copies > 1 { Button("Equip", action: onEquip).buttonStyle(.borderless).font(.caption.weight(.semibold)) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TrainingBattleView: View {
    @ObservedObject var cardStore: CardStore
    let battleID: UUID
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var battle: BattleState? { cardStore.activeBattle?.id == battleID ? cardStore.activeBattle : nil }

    var body: some View {
        NavigationStack {
            Group {
                if let battle, let player = battle.participants.first(where: { !$0.isAI }) {
                    ScrollView {
                        VStack(spacing: AtlasTheme.Space.lg) {
                            objectiveCard(battle)
                            scoreCard(battle)
                            board(battle)
                            hand(player, battle: battle)
                            eventLog(battle)
                        }
                        .padding(AtlasTheme.Space.xl)
                    }
                } else {
                    ContentUnavailableView("Training complete", systemImage: "flag.checkered", description: Text("The encounter result was saved."))
                }
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Guardian training")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { if battle?.winner == nil { cardStore.abandonTraining() }; onClose() } } }
        }
    }

    private func scoreCard(_ battle: BattleState) -> some View {
        StatSectionCard {
            HStack {
                VStack(alignment: .leading) { Text("Dawn").font(.caption).foregroundStyle(.secondary); Text("\(battle.dawnInfluence)").font(.system(size: 34, weight: .bold, design: .rounded)) }
                Spacer()
                VStack { Text(battle.winner == nil ? "Round \(battle.round)/\(BattleState.maximumRounds)" : "Complete").font(.headline); Text("Guardian \(battle.guardianDurability)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                VStack(alignment: .trailing) { Text("Dusk").font(.caption).foregroundStyle(.secondary); Text("\(battle.duskInfluence)").font(.system(size: 34, weight: .bold, design: .rounded)) }
            }
        }
    }

    private func objectiveCard(_ battle: BattleState) -> some View {
        StatSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "scope").foregroundStyle(AtlasTheme.teal).font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your objective").font(.headline)
                    Text("Win by reducing the Guardian to 0, or by reaching 6 Dawn influence before Dusk. Every card advances one of those goals.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func board(_ battle: BattleState) -> some View {
        StatSectionCard {
            VStack(spacing: 12) {
                Text("Seven-hex Beacon").font(.headline)
                Text("Blue is yours · Gold is the Guardian · the center Beacon grants influence.").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(BattleHex.allCases) { hex in
                        let piece = battle.pieces.first { $0.hex == hex }
                        VStack(spacing: 3) {
                            Image(systemName: piece == nil ? (hex == .center ? "dot.radiowaves.left.and.right" : "hexagon") : "shield.fill")
                            Text(hex.title).font(.caption2.weight(hex == .center ? .bold : .regular))
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(piece?.team == .dawn ? AtlasTheme.blue : (piece == nil ? .secondary : AtlasTheme.gold))
                        .background((piece?.team == .dawn ? AtlasTheme.blue : AtlasTheme.gold).opacity(piece == nil ? 0.08 : 0.18), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func hand(_ player: BattleParticipant, battle: BattleState) -> some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                Text(battle.winner == nil ? "Your hand · \(player.energy) energy" : "Encounter result").font(.headline)
                if let winner = battle.winner { Text(winner == .dawn ? "You secured the Beacon." : "The Guardian held this time.").foregroundStyle(winner == .dawn ? AtlasTheme.teal : .secondary) }
                Text("Recommended: play a 1-energy tactic first. You immediately see the result below.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(player.hand, id: \.self) { id in
                    if let instance = cardStore.instances.first(where: { $0.id == id }), let card = CrewfrontCatalog.byID[instance.blueprintID] {
                        Button {
                            cardStore.playCard(instanceID: id, participantID: player.id)
                        } label: {
                            HStack { Image(systemName: card.symbolName); VStack(alignment: .leading) { Text(card.name); Text("\(card.energyCost) energy · \(card.kind.displayName)").font(.caption) }; Spacer(); Image(systemName: "play.fill") }
                        }
                        .buttonStyle(.bordered)
                        .tint(card.energyCost == 1 ? AtlasTheme.blue : .secondary)
                        .disabled(battle.winner != nil || player.energy < card.energyCost)
                    }
                }
            }
        }
    }

    private func eventLog(_ battle: BattleState) -> some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("What just happened").font(.headline)
                ForEach(battle.events.suffix(3)) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(AtlasTheme.teal)
                        VStack(alignment: .leading) { Text(event.title).font(.subheadline.weight(.semibold)); Text(event.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}

private extension BattleHex {
    var title: String {
        switch self { case .center: "Beacon"; case .northEast: "NE"; case .southEast: "SE"; case .southWest: "SW"; case .northWest: "NW"; case .east: "East"; case .west: "West" }
    }
}
