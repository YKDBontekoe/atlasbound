import SwiftUI
import MapKit
import CoreLocation

struct MainMapScreen: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject private var recorder: ActivityRecorder

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var followsUser = true
    @State private var showSettings = false
    @State private var showActivityPicker = false
    @AppStorage("debug.showSimGPSControls") private var showSimGPSControls = false

    init(controller: WorldController, store: TileStore) {
        self.controller = controller
        self.store = store
        self._recorder = ObservedObject(wrappedValue: controller.recorder)
    }

    private var showsSimGPSPad: Bool {
        #if DEBUG
        DevConfig.isSimGPSFeatureAvailable && showSimGPSControls
        #else
        false
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DiscoveryMapView(
                controller: controller,
                store: store,
                recorder: recorder,
                position: $position,
                followsUser: $followsUser,
                showLayers: controller.showLayers
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if controller.isRecording {
                    activeHeader
                } else {
                    idleHeader
                }
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }

            mapSideControls
                .padding(.trailing, 16)
                .padding(.bottom, controller.isRecording ? 300 : 168)

            #if DEBUG
            if showsSimGPSPad {
                DebugLocationPad(controller: controller, followsUser: $followsUser)
                    .padding(.leading, 16)
                    .padding(.bottom, controller.isRecording ? 300 : 168)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            #endif

            VStack(spacing: 12) {
                if let error = recorder.lastErrorMessage {
                    Text(error)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AtlasTheme.finishRed, in: Capsule())
                        .padding(.horizontal, 16)
                }

                if controller.isRecording {
                    activeBottomPanel
                } else {
                    idleBottomSheet
                }
            }
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $controller.showSummary) {
            if let summary = controller.lastSummary {
                ActivitySummaryView(summary: summary) {
                    controller.showSummary = false
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                controller: controller,
                store: store,
                showSimGPSControls: $showSimGPSControls
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showActivityPicker) {
            ActivityPickerSheet(controller: controller)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: showSimGPSControls) { _, enabled in
            #if DEBUG
            if !enabled {
                controller.debugDisableSimulation()
            }
            #else
            _ = enabled
            #endif
        }
        .onAppear {
            #if DEBUG
            if !DevConfig.isSimGPSFeatureAvailable || !showSimGPSControls {
                controller.debugDisableSimulation()
            }
            #endif
        }
    }

    // MARK: - Idle chrome

    private var idleHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AtlasTheme.blue, AtlasTheme.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                Spacer(minLength: 0)

                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Text("\(controller.regionName) · \(controller.discoveredTileCount) tiles")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.94), in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.94), in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                HexShape()
                    .fill(AtlasTheme.teal)
                    .frame(width: 12, height: 13)
                Text("\(nearbyCount) tiles nearby")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.9), in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .padding(.top, 8)
    }

    private var idleBottomSheet: some View {
        HStack(spacing: 14) {
            Button {
                showActivityPicker = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AtlasTheme.blue.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: recorder.activityType.symbolName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AtlasTheme.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(recorder.activityType.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(recorder.activityType.revealWidthLabel) reveal · \(recorder.activityType.tileSize.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Activity type")
            .accessibilityValue(recorder.activityType.displayName)
            .accessibilityHint("Double tap to change activity")

            Spacer(minLength: 8)

            Button {
                controller.startActivity()
                followsUser = true
            } label: {
                Text(recorder.activityType.startButtonTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(AtlasTheme.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 20, y: -2)
        )
        .padding(.horizontal, 12)
    }

    // MARK: - Active chrome

    private var activeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recorder.activityType.activeTitle)
                    .font(.system(size: 28, weight: .bold))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatDuration(recorder.elapsedActive))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AtlasTheme.blue)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            Button {
                recenter()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AtlasTheme.blue)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.95), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var activeBottomPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                liveStat(
                    icon: "mappin.and.ellipse",
                    value: distanceValue,
                    unit: distanceUnit
                )
                divider
                liveStat(
                    icon: "gauge.with.needle",
                    value: String(format: "%.1f", recorder.speedKmh),
                    unit: "km/h"
                )
                divider
                liveStat(
                    icon: "hexagon.fill",
                    value: "\(controller.sessionDiscoveredCount)",
                    unit: "new tiles",
                    tint: AtlasTheme.teal
                )
            }
            .padding(.vertical, 14)
            .background(cardBackground)

            streakCard

            HStack(spacing: 14) {
                Button {
                    controller.togglePause()
                } label: {
                    Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AtlasTheme.blue)
                        .frame(width: 56, height: 56)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                }
                .buttonStyle(.plain)

                Button {
                    controller.stopActivity()
                } label: {
                    Text("Finish")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AtlasTheme.finishRed, in: Capsule())
                        .shadow(color: AtlasTheme.finishRed.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AtlasTheme.teal)
                Text("Discovery streak")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "x%.1f", controller.streakMultiplier))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AtlasTheme.teal)
            }

            ProgressView(value: max(0.08, controller.streakProgress))
                .tint(AtlasTheme.teal)

            HStack {
                Text("Keep exploring to build your streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(streakRemainingLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var mapSideControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Button {
                    recenter()
                } label: {
                    Image(systemName: followsUser ? "location.fill" : "location")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AtlasTheme.blue)
                        .frame(width: 42, height: 42)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .opacity(controller.isRecording ? 0 : 1)

                Button {
                    controller.showLayers.toggle()
                } label: {
                    Image(systemName: "square.3.layers.3d.top.filled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(controller.showLayers ? AtlasTheme.blue : .secondary)
                        .frame(width: 42, height: 42)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Helpers

    private var nearbyCount: Int {
        controller.nearbyUndiscoveredCount(around: recorder.lastLocation?.coordinate)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous)
            .fill(.white)
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 36)
    }

    private var distanceValue: String {
        let meters = recorder.distanceMeters
        if meters >= 1000 {
            return String(format: "%.2f", meters / 1000)
        }
        return String(format: "%.0f", meters)
    }

    private var distanceUnit: String {
        recorder.distanceMeters >= 1000 ? "km" : "m"
    }

    private var streakRemainingLabel: String {
        guard let expires = controller.streakExpiresAt else { return "—" }
        let remaining = max(0, expires.timeIntervalSinceNow)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d remaining", minutes, seconds)
    }

    private func liveStat(icon: String, value: String, unit: String, tint: Color = AtlasTheme.blue) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func recenter() {
        followsUser = true
        guard let location = recorder.lastLocation else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: controller.isRecording ? 650 : 950,
                    longitudinalMeters: controller.isRecording ? 650 : 950
                )
            )
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct SettingsSheet: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @Binding var showSimGPSControls: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Type", selection: Binding(
                        get: { controller.recorder.activityType },
                        set: { controller.setActivityType($0) }
                    )) {
                        ForEach(ActivityType.selectableCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .disabled(controller.isRecording)

                    LabeledContent("Reveal width", value: controller.recorder.activityType.revealWidthLabel)
                    Text("Tile size follows your activity — narrow for walking and running, medium for cycling, hiking, and transit, wide for driving. You can also change this from the map before starting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                if DevConfig.isSimGPSFeatureAvailable {
                    Section("Developer") {
                        Toggle("Show Sim GPS controls", isOn: $showSimGPSControls)
                        Text("Requires ATLASBOUND_ENABLE_SIM_GPS=true in the project `.env` (then run `python3 scripts/sync-env.py` and rebuild).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif

                Section {
                    Button("Clear discovered tiles", role: .destructive) {
                        store.clearCurrentGrid()
                    }
                    .disabled(controller.isRecording)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
