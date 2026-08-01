import SwiftUI

struct JournalTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore
    @ObservedObject var treasureStore: TreasureStore
    @ObservedObject var factoryController: FactoryController

    var body: some View {
        NavigationStack {
            JournalHubView(
                controller: controller,
                store: store,
                activityHistory: activityHistory,
                treasureStore: treasureStore,
                factoryController: factoryController
            )
            .navigationTitle("Journal")
        }
    }
}

struct JournalHubView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore
    @ObservedObject var treasureStore: TreasureStore
    @ObservedObject var factoryController: FactoryController
    @ObservedObject private var inventoryStore: InventoryStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSession: PersistedActivityRecord?

    init(
        controller: WorldController,
        store: TileStore,
        activityHistory: ActivityHistoryStore,
        treasureStore: TreasureStore,
        factoryController: FactoryController
    ) {
        self.controller = controller
        self.store = store
        self.activityHistory = activityHistory
        self.treasureStore = treasureStore
        self.factoryController = factoryController
        self._inventoryStore = ObservedObject(wrappedValue: controller.inventoryStore)
    }

    var body: some View {
        List {
            Section("Today’s Trail") {
                TreasureAdventureCard(store: treasureStore) {}
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                LabeledContent("Progress", value: treasureStore.trailProgressLabel)
                LabeledContent(
                    "Vault keys",
                    value: "\(treasureStore.weeklyVault.keys)/\(TreasureConstants.keysRequiredForVault)"
                )
            }

            Section {
                if inventoryStore.sortedStacks.isEmpty {
                    Text("Explore tiles to gather field finds — materials, boosts, and charges.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(inventoryStore.sortedStacks) { stack in
                        InventoryItemRow(
                            stack: stack,
                            onUse: {
                                _ = controller.performItemAction(itemID: stack.itemID, action: .use)
                            },
                            onActivate: {
                                _ = controller.performItemAction(itemID: stack.itemID, action: .activate)
                            },
                            onSalvage: {
                                _ = controller.performItemAction(itemID: stack.itemID, action: .salvage)
                            },
                            onDiscard: {
                                _ = controller.performItemAction(itemID: stack.itemID, action: .discard)
                            }
                        )
                    }
                }

                NavigationLink {
                    FactoryRecipeBookView(controller: factoryController)
                } label: {
                    Label("Recipe book", systemImage: "book.pages.fill")
                }
                .accessibilityIdentifier("journalRecipeBookLink")
                .accessibilityHint("Opens hand assembly and automated factory recipes.")

                LabeledContent("Finds today", value: "\(inventoryStore.findsClaimedToday)/\(FieldFindConstants.maxFindsPerDay)")
                LabeledContent("Lifetime finds", value: "\(inventoryStore.lifetimeFindsCollected)")

                if let message = inventoryStore.latestActionMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Inventory")
            } footer: {
                Text("Long-press an item to Use, Activate, Salvage, or Discard. Assemble kits and charms from the Recipe book.")
            }

            if !inventoryStore.cartographerPins.isEmpty {
                Section("Pinned tiles") {
                    ForEach(inventoryStore.cartographerPins.suffix(12).reversed()) { pin in
                        LabeledContent(
                            pin.note,
                            value: pin.pinnedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }
            }

            Section("Optional Activity History") {
                if activityHistory.sessions.isEmpty {
                    Text("Track a walk, ride, or other activity from the Map when you want fitness details.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(activityHistory.sessions.suffix(3).reversed())) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            ActivityHistoryRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink("See all tracked activities") {
                        ActivityHistoryView(activityHistory: activityHistory)
                    }
                }
            }

            Section("Relic Collection") {
                if treasureStore.relics.isEmpty {
                    ContentUnavailableView {
                        Label("No relics yet", systemImage: "sparkles")
                    } description: {
                        Text("Complete today’s treasure trail to recover your first relic.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(treasureStore.relics.suffix(12).reversed())) { relic in
                        HStack(spacing: 12) {
                            Image(systemName: relic.theme.symbolName)
                                .foregroundStyle(AtlasTheme.gold)
                                .frame(width: 34, height: 34)
                                .background(AtlasTheme.gold.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(relic.name).font(.subheadline.weight(.semibold))
                                Text("\(relic.landmarkName) · \(relic.source)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(relic.rarity.displayName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(relic.rarity >= .rare ? AtlasTheme.gold : .secondary)
                        }
                    }
                }
            }

            Section("Recent Discoveries") {
                ForEach(Array(store.discoveredTiles.suffix(5).reversed())) { tile in
                    LabeledContent(
                        tile.state.displayName,
                        value: tile.firstVisitedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Today"
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AtlasTheme.canvas(for: colorScheme))
        .sheet(item: $selectedSession) { session in
            ActivitySessionDetailView(session: session) {
                selectedSession = nil
            }
        }
    }
}
