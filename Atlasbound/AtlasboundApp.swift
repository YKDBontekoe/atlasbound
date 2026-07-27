import SwiftUI

@main
struct AtlasboundApp: App {
    @StateObject private var store = TileStore()
    @StateObject private var activityHistory = ActivityHistoryStore()
    @StateObject private var controllerHolder = ControllerHolder()
    @StateObject private var geoGuessrHolder = GeoGuessrHolder()
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if let controller = controllerHolder.controller,
                   let geoController = geoGuessrHolder.controller {
                    RootTabView(
                        controller: controller,
                        store: store,
                        activityHistory: activityHistory,
                        geoGuessrController: geoController
                    )
                } else {
                    ProgressView("Loading world…")
                }
            }
            .preferredColorScheme(
                AppearancePreference(rawValue: appearanceRaw)?.preferredColorScheme
            )
            .onAppear {
                controllerHolder.bootstrap(store: store, activityHistory: activityHistory)
                geoGuessrHolder.bootstrap()
            }
        }
    }
}

@MainActor
final class ControllerHolder: ObservableObject {
    @Published var controller: WorldController?

    func bootstrap(store: TileStore, activityHistory: ActivityHistoryStore) {
        guard controller == nil else { return }
        controller = WorldController(store: store, activityHistory: activityHistory)
    }
}

@MainActor
final class GeoGuessrHolder: ObservableObject {
    @Published var controller: GeoGuessrController?

    func bootstrap() {
        guard controller == nil else { return }
        let store = GeoGuessrStore()
        let gcManager = GameCenterManager()
        gcManager.authenticate()
        controller = GeoGuessrController(store: store, gameCenterManager: gcManager)
    }
}
