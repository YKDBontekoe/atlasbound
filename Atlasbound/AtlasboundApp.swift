import SwiftUI

@main
struct AtlasboundApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var store = TileStore()
    @StateObject private var activityHistory = ActivityHistoryStore()
    @StateObject private var regionLookup = RegionLookupStore()
    @StateObject private var gameCenterManager = GameCenterManager()
    @StateObject private var treasureStore = TreasureStore()
    @StateObject private var inventoryStore = InventoryStore()
    @StateObject private var factoryStore = FactoryStore()
    @StateObject private var idleStore = IdleStore()
    @StateObject private var skillStore = SkillStore()
    @StateObject private var controllerHolder = ControllerHolder()
    @StateObject private var factoryHolder = FactoryHolder()
    @StateObject private var pinpointHolder = PinpointHolder()
    @StateObject private var cloudStateSync = CloudStateSync()
    @State private var cloudBootstrapStarted = false
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading {
                    LoadingWorldView()
                } else if auth.session == nil {
                    AuthView(auth: auth)
                } else if auth.needsProfileSetup {
                    ProfileSetupView(auth: auth)
                } else if let controller = controllerHolder.controller,
                   let factoryController = factoryHolder.controller,
                   let pinpointController = pinpointHolder.controller {
                    RootTabView(
                        auth: auth,
                        controller: controller,
                        store: store,
                        activityHistory: activityHistory,
                        regionLookup: regionLookup,
                        pinpointController: pinpointController,
                        factoryController: factoryController
                    )
                } else {
                    LoadingWorldView()
                }
            }
            .preferredColorScheme(
                AppearancePreference(rawValue: appearanceRaw)?.preferredColorScheme
            )
            .onAppear {
                bootstrapWorldIfAuthenticated()
            }
            .onChange(of: auth.session?.user.id) { _, newValue in
                if newValue == nil {
                    cloudStateSync.stop()
                    cloudBootstrapStarted = false
                } else {
                    bootstrapWorldIfAuthenticated()
                }
            }
            .onOpenURL { url in
                Task { await auth.handle(url: url) }
            }
        }
    }

    @MainActor
    private func bootstrapWorldIfAuthenticated() {
        guard auth.session != nil else { return }
        guard !cloudBootstrapStarted else { return }
        cloudBootstrapStarted = true
        Task {
            pinpointHolder.bootstrap(tileStore: store, gameCenterManager: gameCenterManager)
            await store.hydrateFromCloud()
            await cloudStateSync.hydrate(
                activityHistory: activityHistory,
                regionLookup: regionLookup,
                treasure: treasureStore,
                inventory: inventoryStore,
                factory: factoryStore,
                idle: idleStore,
                skills: skillStore,
                pinpoint: pinpointHolder.store!
            )
            bootstrapControllers()
        }
    }

    @MainActor
    private func bootstrapControllers() {
        gameCenterManager.authenticate()
        controllerHolder.bootstrap(
            store: store,
            activityHistory: activityHistory,
            regionLookup: regionLookup,
            gameCenterManager: gameCenterManager,
            treasureStore: treasureStore,
            inventoryStore: inventoryStore,
            idleStore: idleStore,
            skillStore: skillStore
        )
        factoryHolder.bootstrap(
            store: factoryStore,
            tileStore: store,
            inventoryStore: inventoryStore,
            skillStore: skillStore
        )
        pinpointHolder.bootstrap(tileStore: store, gameCenterManager: gameCenterManager)
        if let pinpointStore = pinpointHolder.store {
            cloudStateSync.start(
                tileStore: store,
                activityHistory: activityHistory,
                regionLookup: regionLookup,
                treasure: treasureStore,
                inventory: inventoryStore,
                factory: factoryStore,
                idle: idleStore,
                skills: skillStore,
                pinpoint: pinpointStore
            )
        }
    }
}

@MainActor
final class FactoryHolder: ObservableObject {
    @Published var controller: FactoryController?

    func bootstrap(
        store: FactoryStore,
        tileStore: TileStore,
        inventoryStore: InventoryStore,
        skillStore: SkillStore
    ) {
        guard controller == nil else { return }
        controller = FactoryController(
            store: store,
            tileStore: tileStore,
            inventoryStore: inventoryStore,
            skillStore: skillStore
        )
        controller?.advance()
    }
}

@MainActor
final class ControllerHolder: ObservableObject {
    @Published var controller: WorldController?

    func bootstrap(
        store: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore,
        gameCenterManager: GameCenterManager,
        treasureStore: TreasureStore,
        inventoryStore: InventoryStore,
        idleStore: IdleStore,
        skillStore: SkillStore
    ) {
        guard controller == nil else { return }
        controller = WorldController(
            store: store,
            activityHistory: activityHistory,
            regionLookup: regionLookup,
            gameCenterManager: gameCenterManager,
            treasureStore: treasureStore,
            inventoryStore: inventoryStore,
            idleStore: idleStore,
            skillStore: skillStore
        )
    }
}

@MainActor
final class PinpointHolder: ObservableObject {
    @Published var controller: PinpointController?
    private(set) var store: PinpointStore?

    func bootstrap(tileStore: TileStore, gameCenterManager: GameCenterManager) {
        guard controller == nil else { return }
        let store = PinpointStore()
        self.store = store
        controller = PinpointController(store: store, tileStore: tileStore, gameCenterManager: gameCenterManager)
    }
}
