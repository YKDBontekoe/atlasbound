import SwiftUI

@main
struct AtlasboundApp: App {
    @StateObject private var store = TileStore()
    @StateObject private var controllerHolder = ControllerHolder()
    @StateObject private var geoStore = GeoGuessrStore()
    @StateObject private var gameCenterManager = GameCenterManager()
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if let controller = controllerHolder.controller {
                    RootTabView(
                        controller: controller,
                        store: store,
                        geoStore: geoStore,
                        gameCenterManager: gameCenterManager
                    )
                } else {
                    ProgressView("Loading world…")
                }
            }
            .preferredColorScheme(
                AppearancePreference(rawValue: appearanceRaw)?.preferredColorScheme
            )
            .onAppear {
                controllerHolder.bootstrap(store: store)
                gameCenterManager.authenticate()
            }
        }
    }
}

@MainActor
final class ControllerHolder: ObservableObject {
    @Published var controller: WorldController?

    func bootstrap(store: TileStore) {
        guard controller == nil else { return }
        controller = WorldController(store: store)
    }
}
