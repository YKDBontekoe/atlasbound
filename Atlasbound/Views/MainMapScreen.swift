import SwiftUI
import MapKit
import CoreLocation

struct MainMapScreen: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var factoryController: FactoryController
    @ObservedObject private var recorder: ActivityRecorder
    @ObservedObject private var treasureStore: TreasureStore
    @ObservedObject private var inventoryStore: InventoryStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var followsUser = true
    @State private var showSettings = false
    @State private var showActivityPicker = false
    @State private var showExpeditionSheet = false
    @State private var showMapOptions = false
    @State private var showTreasureSheet = false
    @State private var showDailyChallenge = false
    @State private var showFactoryBuildSheet = false
    @State private var factoryPreviewTileID: String?
    @State private var presentedSummary: ActivitySummary?
    @AppStorage("debug.showSimGPSControls") private var showSimGPSControls = false
    @AppStorage(OnboardingPreference.storageKey) private var onboardingVersion = 0
    @AppStorage("map.style") private var mapStyleRaw = LiveMapStyle.explorer.rawValue
    @AppStorage("map.dataLayer") private var mapDataLayerRaw = LiveMapDataLayer.mastery.rawValue
    @AppStorage("map.uses3D") private var prefers3DMap = false
    @AppStorage("map.layer.mastery") private var showsMasteryLayer = true
    @AppStorage("map.layer.places") private var showsPlacesLayer = true
    @AppStorage("map.layer.fog") private var showsFogLayer = true
    @AppStorage("map.layer.frontier") private var showsFrontierLayer = true
    @AppStorage("map.layer.factory") private var showsFactoryLayer = true
    @State private var onboardingStep = 0
    /// Measured height of the bottom chrome stack; keeps side controls clear of treasure/missions panels.
    @State private var bottomChromeHeight: CGFloat = 220

    init(
        controller: WorldController,
        store: TileStore,
        factoryController: FactoryController
    ) {
        self.controller = controller
        self.store = store
        self.factoryController = factoryController
        self._recorder = ObservedObject(wrappedValue: controller.recorder)
        self._treasureStore = ObservedObject(wrappedValue: controller.treasureStore)
        self._inventoryStore = ObservedObject(wrappedValue: controller.inventoryStore)
    }

    private var showsSimGPSPad: Bool {
        #if DEBUG
        DevConfig.isSimGPSFeatureAvailable && showSimGPSControls
        #else
        false
        #endif
    }

    private var dailyChallenge: DailyChallengeSnapshot {
        DailyChallengeEngine().snapshot(tiles: store.discoveredTiles)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DiscoveryMapView(
                controller: controller,
                store: store,
                recorder: recorder,
                position: $position,
                followsUser: $followsUser,
                mapStyle: availableMapStyle,
                dataLayer: availableMapDataLayer,
                is3DEnabled: uses3DMap,
                showsMasteryLayer: showsMasteryLayer,
                showsPlacesLayer: showsPlacesLayer,
                showsFogLayer: showsFogLayer,
                showsFrontierLayer: showsFrontierLayer,
                showsFactoryLayer: showsFactoryLayer,
                factoryController: factoryController,
                factoryPreviewTileID: $factoryPreviewTileID,
                onTreasureTap: { showTreasureSheet = true }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if controller.isRecording {
                    activeHeader
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if !factoryController.isBuildModeActive {
                    idleHeader
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .animation(AtlasMotion.chrome, value: controller.isRecording)

            mapSideControls
                .padding(.trailing, 16)
                .padding(.bottom, bottomChromeHeight)
                .animation(AtlasMotion.chrome, value: bottomChromeHeight)

            #if DEBUG
            if showsSimGPSPad {
                DebugLocationPad(controller: controller, followsUser: $followsUser)
                    .padding(.leading, 16)
                    .padding(.bottom, bottomChromeHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .animation(AtlasMotion.chrome, value: bottomChromeHeight)
            }
            #endif

            VStack(spacing: 12) {
                if factoryController.isBuildModeActive, let tileID = factoryPreviewTileID {
                    factoryBuildPreview(tileID: tileID)
                        .padding(.horizontal, 12)
                }
                if let effect = inventoryStore.primaryActiveEffect {
                    ActiveEffectChip(effect: effect)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

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
                        dailyChallenge: dailyChallenge,
                        onDailyTap: { showDailyChallenge = true },
                        onExpeditionsTap: { showExpeditionSheet = true }
                    )
                    idleBottomSheet
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 8)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: BottomChromeHeightKey.self,
                        value: geo.size.height
                    )
                }
            }
            .onPreferenceChange(BottomChromeHeightKey.self) { height in
                guard height > 0 else { return }
                bottomChromeHeight = height
            }
            .animation(AtlasMotion.chrome, value: controller.isRecording)
            .animation(AtlasMotion.fade, value: controller.sessionFeedback.map(\.id))
            .animation(AtlasMotion.fade, value: inventoryStore.primaryActiveEffect?.id)
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
                factoryController: factoryController,
                showSimGPSControls: $showSimGPSControls
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showActivityPicker) {
            ActivityPickerSheet(controller: controller, startsTrackingOnSelection: true)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMapOptions) {
            LiveMapOptionsSheet(
                selectedStyleRaw: $mapStyleRaw,
                selectedDataLayerRaw: $mapDataLayerRaw,
                uses3DMap: $prefers3DMap,
                showsMastery: $showsMasteryLayer,
                showsPlaces: $showsPlacesLayer,
                showsFog: $showsFogLayer,
                showsFrontier: $showsFrontierLayer,
                showsFactory: $showsFactoryLayer,
                explorerLevel: ExplorerProgressionEngine().level(
                    forTotalXP: store.discoveryXPTotal + store.familiarityXPTotal
                )
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTreasureSheet) {
            TreasureDetailSheet(controller: controller, store: treasureStore)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDailyChallenge) {
            DailyChallengeSheet(snapshot: dailyChallenge)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFactoryBuildSheet) {
            FactoryBuildCatalogSheet(controller: factoryController) {
                showFactoryBuildSheet = false
                factoryPreviewTileID = nil
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(
            isPresented: Binding(
                get: { factoryController.selectedStructureID != nil },
                set: { if !$0 { factoryController.selectedStructureID = nil } }
            )
        ) {
            if let tileID = factoryController.selectedStructureID {
                FactoryStructureInspector(controller: factoryController, tileID: tileID)
                    .presentationDetents([.medium, .large])
            }
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
        .sheet(item: $inventoryStore.latestPickup) { pickup in
            FieldFindPickupSheet(pickup: pickup) {
                inventoryStore.dismissPickup()
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
            factoryController.updatePlayerLocation(recorder.lastLocation)
            factoryController.advance()
            #if DEBUG
            if !DevConfig.isSimGPSFeatureAvailable || !showSimGPSControls {
                controller.debugDisableSimulation()
            }
            #endif
        }
        .onChange(of: recorder.lastLocation?.timestamp) { _, _ in
            factoryController.updatePlayerLocation(recorder.lastLocation)
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
            Button {
                showDailyChallenge = true
            } label: {
                DailyChallengeCompactTracker(snapshot: dailyChallenge)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activeDailyChallenge")

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

                if explorerLevel >= ExplorerProgressionEngine.threeDMapRequiredLevel {
                    Button {
                        prefers3DMap.toggle()
                        AtlasHaptics.select()
                    } label: {
                        Image(systemName: "cube.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(uses3DMap ? AtlasTheme.blue : .secondary)
                            .frame(width: 42, height: 42)
                            .rotation3DEffect(
                                .degrees(uses3DMap ? 18 : 0),
                                axis: (x: 1, y: 1, z: 0)
                            )
                            .animation(AtlasMotion.camera, value: uses3DMap)
                    }
                    .buttonStyle(GlassButtonStyle(shape: .circle))
                    .accessibilityLabel(uses3DMap ? "Disable 3D map" : "Enable 3D map")
                }

                Button {
                    showFactoryBuildSheet = true
                    AtlasHaptics.select()
                } label: {
                    Image(systemName: factoryController.isBuildModeActive ? "hammer.fill" : "hammer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(factoryController.isBuildModeActive ? AtlasTheme.gold : .secondary)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(GlassButtonStyle(shape: .circle))
                .accessibilityLabel("Build factory")
                .accessibilityHint("Opens construction kits. Placement requires your current or an adjacent discovered hex.")

                Button {
                    showMapOptions = true
                    AtlasHaptics.select()
                } label: {
                    Image(systemName: "square.3.layers.3d.top.filled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(hasCustomMapPresentation ? AtlasTheme.blue : .secondary)
                        .frame(width: 42, height: 42)
                        .animation(AtlasMotion.fade, value: hasCustomMapPresentation)
                }
                .buttonStyle(GlassButtonStyle(shape: .circle))
                .accessibilityLabel("Map styles and layers")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var hasCustomMapPresentation: Bool {
        mapStyleRaw != LiveMapStyle.explorer.rawValue ||
            mapDataLayerRaw != LiveMapDataLayer.mastery.rawValue ||
            uses3DMap ||
            !showsMasteryLayer ||
            !showsPlacesLayer ||
            !showsFogLayer ||
            !showsFrontierLayer ||
            !showsFactoryLayer
    }

    private var explorerLevel: Int {
        ExplorerProgressionEngine().level(
            forTotalXP: store.discoveryXPTotal + store.familiarityXPTotal
        )
    }

    private var availableMapStyle: LiveMapStyle {
        let selected = LiveMapStyle(rawValue: mapStyleRaw) ?? .explorer
        return selected.requiredLevel <= explorerLevel ? selected : .explorer
    }

    private var availableMapDataLayer: LiveMapDataLayer {
        let selected = LiveMapDataLayer(rawValue: mapDataLayerRaw) ?? .mastery
        return selected.requiredLevel <= explorerLevel ? selected : .mastery
    }

    private var uses3DMap: Bool {
        prefers3DMap && explorerLevel >= ExplorerProgressionEngine.threeDMapRequiredLevel
    }

    private func factoryBuildPreview(tileID: String) -> some View {
        let validation = factoryController.validation(for: tileID)
        return HStack(spacing: 12) {
            Image(systemName: validation.isAllowed ? "checkmark.hexagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(validation.isAllowed ? AtlasTheme.teal : AtlasTheme.finishRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(factoryController.selectedBuildDefinition?.name ?? "Construction")
                    .font(.subheadline.weight(.semibold))
                Text(validation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let tile = store.tiles[tileID],
                   tile.state.rawValue >= TileState.explored.rawValue {
                    let deposit = ConstructionEngine().deposit(for: tileID)
                    Text("\(deposit.kind.displayName) · \(deposit.capacity) units")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(deposit.kind == .empty ? .secondary : AtlasTheme.gold)
                }
            }
            Spacer()
            if validation.isAllowed {
                Button("Place") {
                    if factoryController.placeSelected(at: tileID) {
                        factoryPreviewTileID = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AtlasTheme.teal)
                .accessibilityLabel("Place \(factoryController.selectedBuildDefinition?.name ?? "structure")")
                .accessibilityHint("Consumes one kit and constructs on the selected hex.")
            }
            Button {
                factoryPreviewTileID = nil
                factoryController.selectBuildDefinition(nil)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Cancel construction")
        }
        .padding(12)
        .background(cardBackground)
        .accessibilityIdentifier("factoryBuildPreview")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(factoryController.selectedBuildDefinition?.name ?? "Construction preview")
        .accessibilityValue(validation.message)
        .accessibilityHint(
            validation.isAllowed
                ? "Choose Place to construct on this hex."
                : "Select another hex or resolve the stated requirement."
        )
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
            if uses3DMap {
                position = .camera(
                    MapCamera(
                        centerCoordinate: location.coordinate,
                        distance: span,
                        heading: 0,
                        pitch: 58
                    )
                )
            } else {
                position = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: span,
                        longitudinalMeters: span
                    )
                )
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        StatsFormat.clockDuration(interval)
    }
}

struct SettingsSheet: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var factoryController: FactoryController
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
                    Button("Clear world and factory", role: .destructive) {
                        store.clearAtlas()
                        controller.inventoryStore.clearClaimedFindIDs()
                        factoryController.clearFactory()
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

private enum BottomChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
