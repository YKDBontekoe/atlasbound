import SwiftUI

@main
struct AtlasboundApp: App {
    @StateObject private var store = TileStore()
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
                controllerHolder.bootstrap(store: store)
                pinpointHolder.bootstrap(tileStore: store)
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
