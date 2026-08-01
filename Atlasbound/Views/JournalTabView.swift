import SwiftUI

struct JournalTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore
    @ObservedObject var treasureStore: TreasureStore
    @ObservedObject private var inventoryStore: InventoryStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSession: PersistedActivityRecord?
    @State private var showAssembleSheet = false

    init(
        controller: WorldController,
        store: TileStore,
        activityHistory: ActivityHistoryStore,
        treasureStore: TreasureStore
    ) {
        self.controller = controller
        self.store = store
        self.activityHistory = activityHistory
        self.treasureStore = treasureStore
        self._inventoryStore = ObservedObject(wrappedValue: controller.inventoryStore)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AtlasTheme.Space.lg) {
                    trailCard
                        .staggeredAppear(index: 0)
                    inventoryCard
                        .staggeredAppear(index: 1)
                    if !inventoryStore.cartographerPins.isEmpty {
                        pinsCard
                            .staggeredAppear(index: 2)
                    }
                    activityHistoryCard
                        .staggeredAppear(index: 3)
                    relicsCard
                        .staggeredAppear(index: 4)
                    if !store.discoveredTiles.isEmpty {
                        recentDiscoveriesCard
                            .staggeredAppear(index: 5)
                    }
                }
                .padding(AtlasTheme.Space.xl)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Journal")
            .sheet(item: $selectedSession) { session in
                ActivitySessionDetailView(session: session) {
                    selectedSession = nil
                }
            }
            .sheet(isPresented: $showAssembleSheet) {
                AssembleSheet(controller: controller)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Today’s Trail

    private var trailCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Today’s Trail",
                    subtitle: "Follow clues to recover relics and vault keys.",
                    systemImage: "map.fill",
                    accent: AtlasTheme.gold
                )

                TreasureAdventureCard(store: treasureStore, usesGlassChrome: false) {}

                Divider().overlay(AtlasTheme.divider(for: colorScheme))

                AtlasMetricRow(
                    label: "Progress",
                    value: treasureStore.trailProgressLabel,
                    systemImage: "flag.checkered"
                )
                AtlasMetricRow(
                    label: "Vault keys",
                    value: "\(treasureStore.weeklyVault.keys)/\(TreasureConstants.keysRequiredForVault)",
                    valueColor: treasureStore.weeklyVault.keys > 0 ? AtlasTheme.gold : .primary,
                    systemImage: "key.fill"
                )
            }
        }
    }

    // MARK: - Inventory

    private var inventoryCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Inventory",
                    subtitle: "Field finds, materials, and charges from the trail.",
                    systemImage: "shippingbox.fill",
                    accent: AtlasTheme.teal
                )

                if inventoryStore.sortedStacks.isEmpty {
                    AtlasEmptyState(
                        title: "Pack is empty",
                        message: "Explore tiles to gather field finds — materials, boosts, and charges.",
                        systemImage: "shippingbox",
                        artName: "FieldKitMark",
                        accent: AtlasTheme.teal,
                        actionTitle: "Assemble…",
                        action: { showAssembleSheet = true }
                    )
                } else {
                    ForEach(Array(inventoryStore.sortedStacks.enumerated()), id: \.element.id) { index, stack in
                        if index > 0 {
                            Divider().overlay(AtlasTheme.divider(for: colorScheme))
                        }
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

                    Button {
                        showAssembleSheet = true
                    } label: {
                        AtlasChromeLinkRow(
                            title: "Assemble…",
                            systemImage: "hammer.fill",
                            subtitle: "Craft kits from materials in your pack.",
                            accent: AtlasTheme.blue,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(AtlasTheme.divider(for: colorScheme))

                AtlasMetricRow(
                    label: "Finds today",
                    value: "\(inventoryStore.findsClaimedToday)/\(FieldFindConstants.maxFindsPerDay)"
                )
                AtlasMetricRow(
                    label: "Lifetime finds",
                    value: "\(inventoryStore.lifetimeFindsCollected)"
                )

                if let message = inventoryStore.latestActionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Long-press an item to Use, Activate, Salvage, or Discard.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Pins

    private var pinsCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Pinned tiles",
                    subtitle: "Cartographer markers saved from the field.",
                    systemImage: "mappin.circle.fill",
                    accent: AtlasTheme.blue
                )

                ForEach(Array(inventoryStore.cartographerPins.suffix(12).reversed().enumerated()), id: \.element.id) { index, pin in
                    if index > 0 {
                        Divider().overlay(AtlasTheme.divider(for: colorScheme))
                    }
                    AtlasMetricRow(
                        label: pin.note,
                        value: pin.pinnedAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "mappin"
                    )
                }
            }
        }
    }

    // MARK: - Activity history

    private var activityHistoryCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Optional Activity History",
                    subtitle: "Fitness details when you track a session from the Map.",
                    systemImage: "figure.walk",
                    accent: AtlasTheme.blue
                )

                if activityHistory.sessions.isEmpty {
                    AtlasEmptyState(
                        title: "No tracked sessions",
                        message: "Track a walk, ride, or other activity from the Map when you want fitness details.",
                        systemImage: "figure.walk.motion",
                        accent: AtlasTheme.blue
                    )
                } else {
                    ForEach(Array(activityHistory.sessions.suffix(3).reversed().enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            Divider().overlay(AtlasTheme.divider(for: colorScheme))
                        }
                        Button {
                            selectedSession = session
                        } label: {
                            ActivityHistoryRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        ActivityHistoryView(activityHistory: activityHistory)
                    } label: {
                        AtlasChromeLinkRow(
                            title: "See all tracked activities",
                            systemImage: "list.bullet.rectangle",
                            accent: AtlasTheme.blue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Relics

    private var relicsCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Relic Collection",
                    subtitle: "Landmarks recovered from treasure trails and vaults.",
                    systemImage: "sparkles",
                    accent: AtlasTheme.gold
                )

                if treasureStore.relics.isEmpty {
                    AtlasEmptyState(
                        title: "No relics yet",
                        message: "Complete today’s treasure trail to recover your first relic.",
                        systemImage: "sparkles",
                        artName: "TreasureCacheMark",
                        accent: AtlasTheme.gold
                    )
                } else {
                    ForEach(Array(treasureStore.relics.suffix(12).reversed().enumerated()), id: \.element.id) { index, relic in
                        if index > 0 {
                            Divider().overlay(AtlasTheme.divider(for: colorScheme))
                        }
                        HStack(spacing: AtlasTheme.Space.md) {
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
                            Spacer(minLength: 0)
                            Text(relic.rarity.displayName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(relic.rarity >= .rare ? AtlasTheme.gold : .secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent discoveries

    private var recentDiscoveriesCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Recent Discoveries",
                    subtitle: "Latest hexes added to your atlas.",
                    systemImage: "hexagon.fill",
                    accent: AtlasTheme.teal
                )

                ForEach(Array(store.discoveredTiles.suffix(5).reversed().enumerated()), id: \.element.id) { index, tile in
                    if index > 0 {
                        Divider().overlay(AtlasTheme.divider(for: colorScheme))
                    }
                    AtlasMetricRow(
                        label: tile.state.displayName,
                        value: tile.firstVisitedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Today"
                    )
                }
            }
        }
    }
}
