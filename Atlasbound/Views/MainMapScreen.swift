import SwiftUI
import MapKit
import CoreLocation

struct MainMapScreen: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject private var recorder: ActivityRecorder
    @ObservedObject private var treasureStore: TreasureStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var followsUser = true
    @State private var showSettings = false
    @State private var showActivityPicker = false
    @State private var showExpeditionSheet = false
    @State private var showLayers = false
    @State private var showTreasureSheet = false
    @State private var presentedSummary: ActivitySummary?
    @AppStorage("debug.showSimGPSControls") private var showSimGPSControls = false
    @AppStorage(OnboardingPreference.storageKey) private var onboardingVersion = 0
    @State private var onboardingStep = 0

    init(controller: WorldController, store: TileStore) {
        self.controller = controller
        self.store = store
        self._recorder = ObservedObject(wrappedValue: controller.recorder)
        self._treasureStore = ObservedObject(wrappedValue: controller.treasureStore)
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
                showLayers: showLayers,
                onTreasureTap: { showTreasureSheet = true }
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
                    TreasureAdventureCard(store: treasureStore) {
                        showTreasureSheet = true
                    }
                    .padding(.horizontal, 12)
                    MapMissionsStrip(
                        controller: controller,
                        store: store,
                        onExpeditionsTap: { showExpeditionSheet = true }
                    )
                    idleBottomSheet
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 8)
            .animation(AtlasMotion.chrome, value: controller.isRecording)
            .animation(AtlasMotion.fade, value: controller.sessionFeedback.map(\.id))
        }
        .overlay {
            if onboardingVersion < OnboardingPreference.currentVersion {
                OnboardingOverlay(step: $onboardingStep) {
                    onboardingVersion = OnboardingPreference.currentVersion
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
            ActivityPickerSheet(controller: controller, startsTrackingOnSelection: true)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTreasureSheet) {
            TreasureDetailSheet(controller: controller, store: treasureStore)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $treasureStore.pendingEncounter) { encounter in
            TreasureEncounterSheet(encounter: encounter) { choice in
                controller.resolveTreasureEncounter(choice: choice)
            }
            .presentationDetents([.medium])
            .interactiveDismissDisabled()
        }
        .sheet(item: $treasureStore.latestReward) { reward in
            RelicRewardSheet(reward: reward) {
                treasureStore.latestReward = nil
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showExpeditionSheet) {
            ExpeditionSheet(controller: controller, store: store)
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
                    Text("\(controller.currentSectorName) · \(controller.currentSectorCompletionPercent)% · 20 m")
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
        VStack(spacing: 10) {
            Button {
                showActivityPicker = true
            } label: {
                Label("Track an activity (optional)", systemImage: "figure.walk.motion")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("trackActivityButton")
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
                Text(controller.isQuickExploring ? "Exploring" : recorder.activityType.activeTitle)
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
                if controller.isTrackingActivity {
                    liveStat(
                        icon: "gauge.with.needle",
                        value: String(format: "%.1f", recorder.speedKmh),
                        unit: "km/h"
                    )
                } else {
                    liveStat(
                        icon: "map.fill",
                        value: treasureStore.trailProgressLabel,
                        unit: "treasure trail"
                    )
                }
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

            if let target = treasureStore.currentTarget {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AtlasTheme.gold)
                    Text(target.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(treasureStore.trailProgressLabel)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AtlasTheme.gold)
                }
                .padding(.horizontal, 12)
            }
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
    @AppStorage(AutomaticExplorationPreference.backgroundKey) private var automaticBackgroundEnabled = false
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

                Section("Automatic exploration") {
                    Toggle("Continue with screen locked", isOn: $automaticBackgroundEnabled)
                        .onChange(of: automaticBackgroundEnabled) { _, enabled in
                            if enabled {
                                controller.recorder.requestAlwaysAuthorizationForAutomaticExploration()
                            }
                            controller.setAutomaticExploration(
                                foreground: true,
                                background: enabled
                            )
                        }
                        .accessibilityIdentifier("automaticBackgroundToggle")
                    Text("Exploration starts automatically while the app is open and never creates fitness records. Screen-locked discovery requires Always location permission and shows the iOS location indicator.")
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
                        store.clearAtlas()
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
