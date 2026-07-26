import SwiftUI

struct RootTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MainMapScreen(controller: controller, store: store)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(0)

            ActivityTabView(controller: controller, store: store)
                .tabItem {
                    Label("Activity", systemImage: "waveform.path.ecg")
                }
                .tag(1)

            ProgressTabView(store: store)
                .tabItem {
                    Label("Progress", systemImage: "flag.fill")
                }
                .tag(2)
        }
        .tint(AtlasTheme.blue)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color.white, for: .tabBar)
        .onChange(of: controller.isRecording) { _, isRecording in
            if isRecording {
                selectedTab = 0
            }
        }
    }
}

struct ActivityTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: controller.recorder.activityType.symbolName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AtlasTheme.blue)
                            .frame(width: 44, height: 44)
                            .background(AtlasTheme.blue.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(controller.isRecording ? controller.recorder.activityType.activeTitle : "Ready to explore")
                                .font(.headline)
                            Text(controller.isRecording
                                  ? "Recording \(controller.recorder.activityType.displayName.lowercased()) tiles"
                                  : controller.recorder.activityType.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(ActivityType.selectableCases, id: \.self) { type in
                        Button {
                            controller.setActivityType(type)
                        } label: {
                            ActivityTypeRow(
                                type: type,
                                isSelected: controller.recorder.activityType == type
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isRecording)
                    }
                } header: {
                    Text("Activity type")
                } footer: {
                    Text(controller.isRecording
                          ? "Finish the current session before switching activities."
                          : "Each activity uses its own reveal grid width.")
                }

                Section("This atlas") {
                    LabeledContent("Activities completed", value: "\(store.activitiesCompleted)")
                    LabeledContent("Tiles discovered", value: "\(store.discoveredTiles.count)")
                    if let summary = controller.lastSummary {
                        LabeledContent("Last session", value: "+\(summary.tilesDiscovered) new · \(formatDistance(summary.distanceMeters))")
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
    }
}

struct ProgressTabView: View {
    @ObservedObject var store: TileStore

    var body: some View {
        NavigationStack {
            List {
                Section("Explorer") {
                    LabeledContent("Discovery XP", value: "\(store.discoveryXPTotal)")
                    LabeledContent("Familiarity XP", value: "\(store.familiarityXPTotal)")
                    LabeledContent("Activities", value: "\(store.activitiesCompleted)")
                }

                Section("Tiles") {
                    ForEach(TileState.allCases.filter { $0 != .fogged }, id: \.self) { state in
                        let count = store.discoveredTiles.filter { $0.state == state }.count
                        LabeledContent(state.displayName, value: "\(count)")
                    }
                }

                Section("Reveal grid") {
                    LabeledContent("Current width", value: store.tileSize.label)
                    Text("Set automatically from your activity type.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Progress")
        }
    }
}
