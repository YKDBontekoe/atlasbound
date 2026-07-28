import SwiftUI
import CoreLocation

struct RootTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore
    @ObservedObject var regionLookup: RegionLookupStore
    @ObservedObject var pinpointController: PinpointController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MainMapScreen(controller: controller, store: store)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .accessibilityIdentifier("mapTab")
                .tag(0)

            PinpointView(controller: pinpointController)
                .tabItem {
                    Label("Pinpoint", systemImage: "scope")
                }
                .accessibilityIdentifier("pinpointTab")
                .tag(1)

            ActivityTabView(
                controller: controller,
                store: store,
                activityHistory: activityHistory
            )
                .tabItem {
                    Label("Activity", systemImage: "waveform.path.ecg")
                }
                .accessibilityIdentifier("activityTab")
                .tag(2)

            ProgressTabView(
                store: store,
                activityHistory: activityHistory,
                regionLookup: regionLookup,
                pinpointStore: pinpointController.store,
                controller: controller
            )
                .tabItem {
                    Label("Progress", systemImage: "flag.fill")
                }
                .accessibilityIdentifier("progressTab")
                .tag(3)
        }
        .tint(AtlasTheme.blue)
        .toolbar(pinpointController.isGameInProgress ? .hidden : .visible, for: .tabBar)
        .toolbarBackground(AtlasTheme.tabBarBackground(for: colorScheme), for: .tabBar)
        .onChange(of: controller.isRecording) { _, isRecording in
            if isRecording {
                selectedTab = 0
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, controller.isRecording {
                store.flushToDiskIfNeeded()
            }
        }
    }
}
