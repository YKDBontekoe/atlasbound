import SwiftUI

@main
struct AtlasboundApp: App {
    init() {
        MapboxConfiguration.configure()
    }

    @StateObject private var auth = AuthStore()
    @StateObject private var store = TileStore()
    @StateObject private var activityHistory = ActivityHistoryStore()
    @StateObject private var regionLookup = RegionLookupStore()
    @StateObject private var treasureStore = TreasureStore()
    @StateObject private var inventoryStore = InventoryStore()
    @StateObject private var factoryStore = FactoryStore()
    @StateObject private var idleStore = IdleStore()
    @StateObject private var skillStore = SkillStore()
    @StateObject private var controllerHolder = ControllerHolder()
    @StateObject private var factoryHolder = FactoryHolder()
    @StateObject private var cloudStateSync = CloudStateSync()
    @State private var cloudBootstrapStarted = false
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue

    private var isUITestMode: Bool {
        ProcessInfo.processInfo.environment["ATLASBOUND_UI_TEST_MODE"] == "1"
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading && !isUITestMode {
                    LoadingWorldView()
                } else if auth.session == nil && !isUITestMode {
                    AuthView(auth: auth)
                } else if auth.needsProfileSetup && !isUITestMode {
                    ProfileSetupView(auth: auth)
                } else if let controller = controllerHolder.controller,
                   let factoryController = factoryHolder.controller {
                    RootTabView(
                        auth: auth,
                        controller: controller,
                        store: store,
                        activityHistory: activityHistory,
                        regionLookup: regionLookup,
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
                let sessionStore = store
                let sessionActivityHistory = activityHistory
                let sessionRegionLookup = regionLookup
                let sessionTreasure = treasureStore
                let sessionInventory = inventoryStore
                let sessionFactory = factoryStore
                let sessionIdle = idleStore
                let sessionSkills = skillStore
                let sessionCloudSync = cloudStateSync
                auth.onSessionEnded = { @MainActor in
                    sessionCloudSync.stop()
                    sessionStore.resetLocalSession()
                    sessionActivityHistory.resetLocalSession()
                    sessionRegionLookup.resetLocalSession()
                    sessionTreasure.resetLocalSession()
                    sessionInventory.resetLocalSession()
                    sessionFactory.resetLocalSession()
                    sessionIdle.resetLocalSession()
                    sessionSkills.resetLocalSession()
                }
                bootstrapWorldIfAuthenticated()
            }
            .onChange(of: auth.session?.user.id) { _, newValue in
                if newValue == nil {
                    resetLocalSession()
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
        guard auth.session != nil || isUITestMode else { return }
        guard !cloudBootstrapStarted else { return }
        cloudBootstrapStarted = true
        Task {
            if auth.session != nil {
                guard await store.hydrateFromCloud() else {
                    cloudBootstrapStarted = false
                    return
                }
                guard await cloudStateSync.hydrate(
                    activityHistory: activityHistory,
                    regionLookup: regionLookup,
                    treasure: treasureStore,
                    inventory: inventoryStore,
                    factory: factoryStore,
                    idle: idleStore,
                    skills: skillStore
                ) else {
                    cloudBootstrapStarted = false
                    return
                }
            }
            bootstrapControllers()
        }
    }

    @MainActor
    private func bootstrapControllers() {
        controllerHolder.bootstrap(
            store: store,
            activityHistory: activityHistory,
            regionLookup: regionLookup,
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
        if auth.session != nil {
            cloudStateSync.start(
                tileStore: store,
                activityHistory: activityHistory,
                regionLookup: regionLookup,
                treasure: treasureStore,
                inventory: inventoryStore,
                factory: factoryStore,
                idle: idleStore,
                skills: skillStore
            )
        }
    }

    @MainActor
    private func resetLocalSession() {
        cloudStateSync.stop()
        store.resetLocalSession()
        activityHistory.resetLocalSession()
        regionLookup.resetLocalSession()
        treasureStore.resetLocalSession()
        inventoryStore.resetLocalSession()
        factoryStore.resetLocalSession()
        idleStore.resetLocalSession()
        skillStore.resetLocalSession()
        controllerHolder.reset()
        factoryHolder.reset()
        cloudBootstrapStarted = false
    }
}

@MainActor
final class FactoryHolder: ObservableObject {
    @Published var controller: FactoryController?

    func reset() {
        controller = nil
    }

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

    func reset() {
        controller = nil
    }

    func bootstrap(
        store: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore,
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
            treasureStore: treasureStore,
            inventoryStore: inventoryStore,
            idleStore: idleStore,
            skillStore: skillStore
        )
    }
}
