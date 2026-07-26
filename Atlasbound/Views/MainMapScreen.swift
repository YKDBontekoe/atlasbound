import SwiftUI
import CoreLocation

struct MainMapScreen: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore

    private var recorder: ActivityRecorder { controller.recorder }

    var body: some View {
        ZStack {
            DiscoveryMapView(controller: controller, store: store, recorder: recorder)
                .ignoresSafeArea()

            FogHintOverlay(discoveredCount: store.discoveredTiles.count)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .sheet(isPresented: $controller.showSummary) {
            if let summary = controller.lastSummary {
                ActivitySummaryView(summary: summary) {
                    controller.showSummary = false
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Atlasbound")
                    .font(.custom("Avenir Next", size: 22).weight(.bold))
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("Tile size", selection: Binding(
                    get: { store.tileSize },
                    set: { controller.setTileSize($0) }
                )) {
                    ForEach(TileSizeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .disabled(controller.isRecording)

                Picker("Activity", selection: Binding(
                    get: { controller.recorder.activityType },
                    set: { controller.recorder.activityType = $0 }
                )) {
                    ForEach(ActivityType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                .disabled(controller.isRecording)

                Button("Clear tiles (\(store.tileSize.label))", role: .destructive) {
                    store.clearCurrentGrid()
                }
                .disabled(controller.isRecording)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0.92), Color(.systemBackground).opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            HStack {
                statChip(title: "Discovered", value: "\(store.discoveredTiles.count)")
                statChip(title: "Discovery XP", value: "\(store.discoveryXPTotal)")
                statChip(title: "Familiarity", value: "\(store.familiarityXPTotal)")
            }

            if controller.isRecording {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(liveStats)
                        .font(.subheadline.monospacedDigit())
                    Spacer()
                }
            }

            if let error = recorder.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                if controller.isRecording {
                    controller.stopActivity()
                } else {
                    controller.startActivity()
                }
            } label: {
                Text(controller.isRecording ? "End Activity" : "Start Activity")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isRecording ? .red : .accentColor)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var statusLine: String {
        let auth = authorizationLabel(recorder.authorizationStatus)
        return "Tiles \(store.tileSize.label) · \(auth)"
    }

    private var liveStats: String {
        let km = recorder.distanceMeters
        let tiles = controller.sessionVisitedTileIDs.count
        if km >= 1000 {
            return String(format: "%.2f km · %d tiles · %d samples", km / 1000, tiles, recorder.samples.count)
        }
        return String(format: "%.0f m · %d tiles · %d samples", km, tiles, recorder.samples.count)
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func authorizationLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Location not set"
        case .restricted: "Location restricted"
        case .denied: "Location denied"
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "When In Use"
        @unknown default: "Location unknown"
        }
    }
}
