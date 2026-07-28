import SwiftUI
import MapKit
import CoreLocation

struct MainMapScreen: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject private var recorder: ActivityRecorder
    @Environment(\.colorScheme) private var colorScheme

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var followsUser = true
    @State private var showSettings = false
    @State private var showActivityPicker = false
    @State private var showExpeditionSheet = false
    @State private var showWorldEventSheet = false
    @State private var showLayers = false
    @State private var presentedSummary: ActivitySummary?
    @AppStorage("debug.showSimGPSControls") private var showSimGPSControls = false
    @AppStorage(OnboardingPreference.storageKey) private var hasCompletedOnboarding = false
    @State private var onboardingStep = 0

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
                showLayers: showLayers
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if controller.isRecording {
                    activeHeader
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    idleHeader
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .animation(AtlasMotion.chrome, value: controller.isRecording)

            mapSideControls
                .padding(.trailing, 16)
                .padding(.bottom, controller.isRecording ? 240 : 72)
                .animation(AtlasMotion.chrome, value: controller.isRecording)

            #if DEBUG
            if showsSimGPSPad {
                DebugLocationPad(controller: controller, followsUser: $followsUser)
                    .padding(.leading, 16)
                    .padding(.bottom, controller.isRecording ? 240 : 72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .animation(AtlasMotion.chrome, value: controller.isRecording)
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
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ForEach(controller.sessionFeedback.suffix(3)) { event in
                    SessionFeedbackToast(event: event)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if controller.isRecording {
                    activeBottomPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    MapMissionsStrip(
                        controller: controller,
                        store: store,
                        onHotspotsTap: { showWorldEventSheet = true },
                        onExpeditionsTap: { showExpeditionSheet = true }
                    )
                    idleBottomSheet
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 8)
            .animation(AtlasMotion.chrome, value: controller.isRecording)
            .animation(AtlasMotion.fade, value: controller.sessionFeedback.map(\.id))
            .animation(AtlasMotion.fade, value: controller.liveWorldEvent?.id)
        }
        .overlay {
            if !hasCompletedOnboarding {
                OnboardingOverlay(step: $onboardingStep) {
                    hasCompletedOnboarding = true
                }
            }
        }
        .sheet(item: $presentedSummary) { summary in
            ActivitySummaryView(summary: summary) {
                presentedSummary = nil
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: controller.lastSummary?.id) { _, newID in
            if newID != nil {
                presentedSummary = controller.lastSummary
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                controller: controller,
                store: store,
                showSimGPSControls: $showSimGPSControls
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showActivityPicker) {
            ActivityPickerSheet(controller: controller)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showExpeditionSheet) {
            ExpeditionSheet(controller: controller, store: store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showWorldEventSheet) {
            WorldEventSheet(controller: controller, store: store)
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
        .task {
            // Pick up UTC event window open/close while the map stays foregrounded.
            while !Task.isCancelled {
                controller.refreshWorldEventPresentation()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .task(id: recorder.lastErrorMessage) {
            guard recorder.lastErrorMessage != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            recorder.clearError()
        }
    }

    // MARK: - Idle chrome

    private var idleHeader: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button {
                showSettings = true
            } label: {
                HStack(spacing: 6) {
                    Text("\(controller.currentSectorName) · \(controller.currentSectorCompletionPercent)% · \(controller.currentGridLabel)")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(GlassButtonStyle(shape: .capsule))

            Spacer(minLength: 0)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(GlassButtonStyle(shape: .circle))
            .accessibilityIdentifier("settingsButton")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
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
                            .frame(width: 40, height: 40)
                        Image(systemName: recorder.activityType.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AtlasTheme.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(recorder.activityType.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
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
            .accessibilityIdentifier("activityPickerButton")
            .accessibilityLabel("Activity type")
            .accessibilityValue(recorder.activityType.displayName)
            .accessibilityHint("Double tap to change activity")

            Spacer(minLength: 8)

            Button {
                controller.startActivity()
                followsUser = true
                AtlasHaptics.success()
            } label: {
                Text(recorder.activityType.startButtonTitle)
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))
        }
        .padding(12)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
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
            }
            .buttonStyle(GlassButtonStyle(shape: .circle))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: AtlasTheme.headerFade(for: colorScheme),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var activeBottomPanel: some View {
        VStack(spacing: 10) {
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
                    tint: AtlasTheme.teal,
                    animatesNumber: true
                )
            }
            .padding(.vertical, 14)
            .background(cardBackground)
            .animation(AtlasMotion.number, value: controller.sessionDiscoveredCount)
            .animation(AtlasMotion.number, value: distanceValue)

            ActiveWorldEventTracker(controller: controller, compact: true)
            ActiveFrontierTracker(controller: controller, compact: true)

            HStack(spacing: 14) {
                Button {
                    controller.togglePause()
                    AtlasHaptics.select()
                } label: {
                    Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AtlasTheme.blue)
                        .frame(width: 48, height: 48)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(GlassButtonStyle(shape: .circle, weight: .regular))

                Button {
                    controller.stopActivity()
                    AtlasHaptics.success()
                } label: {
                    Text("Finish")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.finishRed, shape: .capsule))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
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
                }
                .buttonStyle(GlassButtonStyle(shape: .circle))
                .opacity(controller.isRecording ? 0 : 1)

                Button {
                    showLayers.toggle()
                    AtlasHaptics.select()
                } label: {
                    Image(systemName: "square.3.layers.3d.top.filled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(showLayers ? AtlasTheme.blue : .secondary)
                        .frame(width: 42, height: 42)
                        .scaleEffect(showLayers ? 1.05 : 1)
                        .animation(AtlasMotion.fade, value: showLayers)
                }
                .buttonStyle(GlassButtonStyle(shape: .circle))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        GlassChrome(
            shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
            weight: .regular
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(AtlasTheme.divider(for: colorScheme))
            .frame(width: 1, height: 36)
    }

    private var distanceValue: String {
        StatsFormat.distanceValue(recorder.distanceMeters)
    }

    private var distanceUnit: String {
        StatsFormat.distanceUnit(recorder.distanceMeters)
    }

    private func liveStat(
        icon: String,
        value: String,
        unit: String,
        tint: Color = AtlasTheme.blue,
        animatesNumber: Bool = false
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .animation(animatesNumber ? AtlasMotion.number : nil, value: value)
    }

    private func recenter() {
        followsUser = true
        guard let location = recorder.lastLocation else { return }
        let span = controller.isRecording
            ? AtlasTheme.mapSpanRecordingMeters
            : AtlasTheme.mapSpanIdleMeters
        withAnimation(AtlasMotion.camera) {
            position = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: span,
                    longitudinalMeters: span
                )
            )
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        StatsFormat.clockDuration(interval)
    }
}

struct SettingsSheet: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @Binding var showSimGPSControls: Bool
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(BackgroundRecordingPreference.storageKey) private var backgroundRecordingEnabled = false
    @Environment(\.dismiss) private var dismiss

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: appearanceBinding) {
                        ForEach(AppearancePreference.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Auto follows your device appearance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Recording") {
                    Toggle("Record while screen is off", isOn: $backgroundRecordingEnabled)
                        .onChange(of: backgroundRecordingEnabled) { _, enabled in
                            if enabled {
                                controller.recorder.enableBackgroundRecordingIfAuthorized()
                            } else {
                                controller.recorder.setBackgroundRecordingEnabled(false)
                            }
                        }
                        .accessibilityIdentifier("backgroundRecordingToggle")
                    Text("Requires Always location access. Keeps tile discovery running when the screen locks — useful for Drive and Transit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if backgroundRecordingEnabled,
                       controller.recorder.authorizationStatus != .authorizedAlways {
                        Text("Grant “Always” location in Settings to enable background recording.")
                            .font(.footnote)
                            .foregroundStyle(AtlasTheme.gold)
                    }
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
                        .accessibilityIdentifier("settingsDone")
                }
            }
        }
    }
}
