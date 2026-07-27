import SwiftUI

@main
struct AtlasboundApp: App {
    @StateObject private var store = TileStore()
    @StateObject private var activityHistory = ActivityHistoryStore()
    @StateObject private var regionLookup = RegionLookupStore()
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
                controllerHolder.bootstrap(
                    store: store,
                    activityHistory: activityHistory,
                    regionLookup: regionLookup
                )
                pinpointHolder.bootstrap(tileStore: store)
            }
        }
    }
}

@MainActor
final class ControllerHolder: ObservableObject {
    @Published var controller: WorldController?
    private var gameCenterManager: GameCenterManager?

    func bootstrap(
        store: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore
    ) {
        guard controller == nil else { return }
        let gcManager = gameCenterManager ?? GameCenterManager()
        gameCenterManager = gcManager
        gcManager.authenticate()
        controller = WorldController(
            store: store,
            activityHistory: activityHistory,
            regionLookup: regionLookup,
            gameCenterManager: gcManager
        )
    }
}

@MainActor
final class PinpointHolder: ObservableObject {
    @Published var controller: PinpointController?

    func bootstrap(tileStore: TileStore) {
        guard controller == nil else { return }
        let store = PinpointStore()
        let gcManager = GameCenterManager()
        gcManager.authenticate()
        controller = PinpointController(store: store, tileStore: tileStore, gameCenterManager: gcManager)
    }
}
