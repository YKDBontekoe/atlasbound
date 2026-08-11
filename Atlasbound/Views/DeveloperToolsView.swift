#if DEBUG
import SwiftUI
import CoreLocation

/// Explicitly opt-in local tools. This type is not compiled into Release builds.
struct DeveloperToolsView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var controller: WorldController
    @ObservedObject var tileStore: TileStore
    @ObservedObject var factoryController: FactoryController
    @ObservedObject var cardStore: CardStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Local-only unlocks") {
                    Button("Unlock everything") { unlockEverything() }
                        .tint(AtlasTheme.teal)
                        .disabled(auth.session != nil)
                    Text("Seeds a legendary atlas patch, level 50 XP, all skills/scouts/research, 99 of every item, and all Crewfront cards. It changes only this device’s local test save.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Targeted") {
                    Button("Discover legendary atlas patch") { tileStore.debugUnlockAtlas(around: playerTile) }.disabled(auth.session != nil)
                    Button("Grant Explorer level 50") { tileStore.debugGrantExplorerLevel(50) }.disabled(auth.session != nil)
                    Button("Grant 99 of every item") { grantMaterials() }.disabled(auth.session != nil)
                    Button("Unlock all skill ranks") { controller.skillStore.debugUnlockAll() }.disabled(auth.session != nil)
                    Button("Hire all scouts") { controller.idleStore.debugHireAll() }.disabled(auth.session != nil)
                    Button("Unlock factory research") { factoryController.store.debugUnlockAllResearch() }.disabled(auth.session != nil)
                    Button("Unlock all Crewfront cards") { cardStore.debugUnlockAll() }.disabled(auth.session != nil)
                }
                if auth.session != nil {
                    Section { Text("Sign out before using developer unlocks. This prevents debug data from being synced to an account.").foregroundStyle(.orange) }
                }
                if !confirmation.isEmpty {
                    Section { Text(confirmation).foregroundStyle(AtlasTheme.teal) }
                }
            }
            .navigationTitle("Developer tools")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var playerTile: TileCoordinate {
        let coordinate = controller.recorder.lastLocation?.coordinate ?? WorldController.debugDefaultCoordinate
        return tileStore.tileEngine.axialCoordinate(for: coordinate)
    }

    private func grantMaterials() {
        controller.inventoryStore.deposit(ItemCatalog.all.map { ItemAmount(itemID: $0.id, quantity: 99) })
        confirmation = "All inventory stacks granted."
    }

    private func unlockEverything() {
        tileStore.debugUnlockAtlas(around: playerTile)
        tileStore.debugGrantExplorerLevel(50)
        grantMaterials()
        controller.skillStore.debugUnlockAll()
        controller.idleStore.debugHireAll()
        factoryController.store.debugUnlockAllResearch()
        cardStore.debugUnlockAll()
        confirmation = "Local developer unlock complete."
    }
}
#endif
