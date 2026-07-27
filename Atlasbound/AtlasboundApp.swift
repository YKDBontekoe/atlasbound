import SwiftUI

@main
struct AtlasboundApp: App {
    @StateObject private var store = TileStore()
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
                controllerHolder.bootstrap(store: store)
                geoGuessrHolder.bootstrap()
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
