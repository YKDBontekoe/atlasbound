import SwiftUI

@main
struct AtlasboundApp: App {
    @StateObject private var store = TileStore()
    @StateObject private var activityHistory = ActivityHistoryStore()
    @StateObject private var regionLookup = RegionLookupStore()
    @StateObject private var gameCenterManager = GameCenterManager()
    @StateObject private var treasureStore = TreasureStore()
    @StateObject private var controllerHolder = ControllerHolder()
    @StateObject private var pinpointHolder = PinpointHolder()
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if let controller = controllerHolder.controller,
                   let pinpointController = pinpointHolder.controller {
                    RootTabView(
                        controller: controller,
                        store: store,
                        activityHistory: activityHistory,
                        regionLookup: regionLookup,
                        pinpointController: pinpointController
                    )
                } else {
                    ProgressView("Loading world…")
                }
            }
            .preferredColorScheme(
                AppearancePreference(rawValue: appearanceRaw)?.preferredColorScheme
            )
            .onAppear {
                gameCenterManager.authenticate()
                controllerHolder.bootstrap(
                    store: store,
                    activityHistory: activityHistory,
                    regionLookup: regionLookup,
                    gameCenterManager: gameCenterManager,
                    treasureStore: treasureStore
                )
                pinpointHolder.bootstrap(tileStore: store, gameCenterManager: gameCenterManager)
            }
        }
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
        treasureStore: TreasureStore
    ) {
        guard controller == nil else { return }
        controller = WorldController(
            store: store,
            activityHistory: activityHistory,
            regionLookup: regionLookup,
            gameCenterManager: gameCenterManager,
            treasureStore: treasureStore
        )
    }
}

@MainActor
final class PinpointHolder: ObservableObject {
    @Published var controller: PinpointController?

    func bootstrap(tileStore: TileStore, gameCenterManager: GameCenterManager) {
        guard controller == nil else { return }
        let store = PinpointStore()
        controller = PinpointController(store: store, tileStore: tileStore, gameCenterManager: gameCenterManager)
    }
}
