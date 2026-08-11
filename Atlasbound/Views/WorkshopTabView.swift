import SwiftUI

/// Single tab home for backpack, crafting, factory production, and adventure log.
/// Crafting lives only in the Factory recipe book — not a second Journal assemble sheet.
struct WorkshopTabView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case journal
        case factory
        case decks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .journal: "Journal"
            case .factory: "Factory"
            case .decks: "Decks"
            }
        }
    }

    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore
    @ObservedObject var treasureStore: TreasureStore
    @ObservedObject var factoryController: FactoryController
    @ObservedObject var cardStore: CardStore

    @Environment(\.colorScheme) private var colorScheme
    @State private var pane: Pane = .journal

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Workshop section", selection: $pane) {
                    ForEach(Pane.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("workshopPanePicker")

                Group {
                    switch pane {
                    case .journal:
                        JournalHubView(
                            controller: controller,
                            store: store,
                            activityHistory: activityHistory,
                            treasureStore: treasureStore,
                            factoryController: factoryController
                        )
                    case .factory:
                        FactoryHubView(controller: factoryController)
                    case .decks:
                        DeckWorkshopView(cardStore: cardStore, inventory: controller.inventoryStore)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle(pane.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
