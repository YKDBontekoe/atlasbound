import SwiftUI

struct JournalTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore
    @ObservedObject var treasureStore: TreasureStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSession: PersistedActivityRecord?

    var body: some View {
        NavigationStack {
            ZStack {
                AtlasTheme.canvas(for: colorScheme)
                    .ignoresSafeArea()

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
            }
            .navigationTitle("Journal")
            .sheet(item: $selectedSession) { session in
                ActivitySessionDetailView(session: session) {
                    selectedSession = nil
                }
            }
        }
    }
}
