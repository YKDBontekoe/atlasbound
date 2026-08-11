import SwiftUI
import CoreLocation
import UIKit
import MapboxMaps

struct MainMapScreen: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var factoryController: FactoryController
    @ObservedObject private var recorder: ActivityRecorder
    @ObservedObject private var treasureStore: TreasureStore
    @ObservedObject private var weatherStore: WeatherStore
    @ObservedObject private var inventoryStore: InventoryStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var position: Viewport = .followPuck(zoom: 15, pitch: 42)
    @State private var followsUser = true
    @State private var showSettings = false
    @State private var showAuthSheet = false
    @State private var showActivityPicker = false
    @State private var showExpeditionSheet = false
    @State private var showMapOptions = false
    @State private var showTreasureSheet = false
    @State private var showDailyChallenge = false
    @State private var showTerritorySheet = false
    @State private var showIdleScoutsSheet = false
    @State private var showFactoryBuildSheet = false
    @State private var selectedPulse: AtlasPulse?
    @State private var factoryPreviewTileID: String?
    @State private var selectedTileID: String?
    @State private var presentedSummary: ActivitySummary?
    @AppStorage("debug.showSimGPSControls") private var showSimGPSControls = false
    @AppStorage(OnboardingPreference.storageKey) private var onboardingVersion = 0
    @AppStorage(WelcomePreference.explorationStartedKey) private var explorationStarted = false
    @AppStorage("map.dataLayer") private var mapDataLayerRaw = LiveMapDataLayer.mastery.rawValue
    @AppStorage("map.layer.mastery") private var showsMasteryLayer = true
    @AppStorage("map.layer.places") private var showsPlacesLayer = true
    @AppStorage("map.layer.frontier") private var showsFrontierLayer = true
    @AppStorage("map.layer.factory") private var showsFactoryLayer = true
    @State private var onboardingStep = 0
    @State private var isIdleAdventureExpanded = false

    init(
        auth: AuthStore,
        controller: WorldController,
        store: TileStore,
        factoryController: FactoryController
    ) {
        self.auth = auth
        self.controller = controller
        self.store = store
        self.factoryController = factoryController
        self._recorder = ObservedObject(wrappedValue: controller.recorder)
        self._treasureStore = ObservedObject(wrappedValue: controller.treasureStore)
        self._weatherStore = ObservedObject(wrappedValue: controller.weatherStore)
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

    private var shouldShowTerritoryCard: Bool {
        let presence = controller.territoryPresence
        return presence.canClaim
            || presence.canSetHome
            || presence.isClaimed
            || presence.claimCount > 0
            || presence.completionPercent >= 10
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DiscoveryMapView(
                controller: controller,
                store: store,
                recorder: recorder,
                position: $position,
                followsUser: $followsUser,
                selectedTileID: $selectedTileID,
                dataLayer: availableMapDataLayer,
                showsMasteryLayer: showsMasteryLayer,
                showsPlacesLayer: showsPlacesLayer,
                showsFrontierLayer: showsFrontierLayer,
                showsFactoryLayer: showsFactoryLayer,
                factoryController: factoryController,
                factoryPreviewTileID: $factoryPreviewTileID,
                onLandmarkQuestTap: { controller.focusLandmarkQuest() },
                onPulseTap: { selectedPulse = $0 }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                weatherHeader
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

            if recorder.authorizationStatus == .denied || recorder.authorizationStatus == .restricted {
                locationPermissionBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 70)
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            mapSideControls
                .padding(.trailing, 16)
                .padding(.bottom, controller.isRecording ? 240 : 16)
                .animation(AtlasMotion.chrome, value: controller.isRecording)

            #if DEBUG
            if showsSimGPSPad {
                DebugLocationPad(controller: controller, followsUser: $followsUser)
                    .padding(.leading, 16)
                    .padding(.bottom, controller.isRecording ? 240 : 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .animation(AtlasMotion.chrome, value: controller.isRecording)
            }
            #endif

            VStack(spacing: 12) {
                if let selectedTileID, !factoryController.isBuildModeActive {
                    TileIntelPanel(
                        tileID: selectedTileID,
                        store: store,
                        controller: controller,
                        factoryController: factoryController,
                        onDismiss: { self.selectedTileID = nil }
                    )
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
                    idleAdventureChrome
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 8)
            .animation(AtlasMotion.chrome, value: controller.isRecording)
            .animation(AtlasMotion.panel, value: isIdleAdventureExpanded)
            .animation(AtlasMotion.fade, value: controller.sessionFeedback.map(\.id))
            .animation(AtlasMotion.fade, value: inventoryStore.primaryActiveEffect?.id)
            .animation(AtlasMotion.panel, value: selectedTileID)
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
        .onChange(of: controller.cameraMoment?.id) { _, _ in
            guard let moment = controller.cameraMoment else { return }
            playCameraMoment(moment)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                auth: auth,
                controller: controller,
                store: store,
                factoryController: factoryController,
                showSimGPSControls: $showSimGPSControls
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthView(auth: auth)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showActivityPicker) {
            ActivityPickerSheet(controller: controller, startsTrackingOnSelection: true)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMapOptions) {
            LiveMapOptionsSheet(
                selectedDataLayerRaw: $mapDataLayerRaw,
                showsMastery: $showsMasteryLayer,
                showsPlaces: $showsPlacesLayer,
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
            DailyChallengeSheet(controller: controller, snapshot: dailyChallenge)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showIdleScoutsSheet) {
            IdleScoutsSheet(controller: controller)
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
        .sheet(item: $controller.latestIdleWatch) { watch in
            IdleWatchReportSheet(summary: watch) {
                controller.dismissIdleWatch()
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $controller.latestWorldBriefing) { briefing in
            WorldBriefingSheet(briefing: briefing, controller: controller) { pulseID in
                guard let pulse = controller.activePulses.first(where: { $0.id == pulseID }) else {
                    return false
                }
                selectedPulse = pulse
                return true
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedPulse) { pulse in
            PulseDetailSheet(controller: controller, pulse: pulse)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showExpeditionSheet) {
            ExpeditionSheet(controller: controller, store: store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTerritorySheet) {
            TerritoryManageSheet(controller: controller)
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
            // The map is the default exploration surface. Start foreground
            // location monitoring here so live discovery, landmark quests,
            // and the frontier all have an actual player anchor.
            if explorationStarted || auth.session != nil {
                controller.prepareLocation()
            }
            controller.catchUpIdleOnForeground()
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

    private var weatherHeader: some View {
        let snapshot = weatherStore.snapshots.values
            .filter { !$0.isStale }
            .sorted { $0.observedAt > $1.observedAt }
            .first
        return Group {
            if let snapshot {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.condition.symbolName)
                    Text("\(snapshot.condition.displayName) · \(Int(snapshot.temperatureC.rounded()))°C")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.62), in: Capsule())
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Regional weather: \(snapshot.condition.displayName), \(Int(snapshot.temperatureC.rounded())) degrees Celsius")
            }
        }
    }

    private var locationPermissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(AtlasTheme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Location is paused")
                    .font(.subheadline.weight(.semibold))
                Text("Allow location in Settings to reveal nearby tiles and treasure arrivals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("locationPermissionBanner")
    }

    // MARK: - Idle chrome

    private var idleHeader: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button {
                showTerritorySheet = true
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
            .accessibilityIdentifier("sectorTerritoryButton")
            .accessibilityLabel(
                "\(controller.currentSectorName), \(controller.currentSectorCompletionPercent) percent explored"
            )
            .accessibilityHint("Opens territory claims")

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

    private var idleAdventureChrome: some View {
        Group {
            if isIdleAdventureExpanded {
                VStack(spacing: 12) {
                    PulseWorldCard(controller: controller) { pulse in
                        selectedPulse = pulse
                    }

                    if auth.session == nil {
                        sharedAdventurePrompt
                            .padding(.horizontal, 12)
                    }
                    TreasureAdventureCard(
                        store: treasureStore,
                        isPreparing: controller.isPreparingTreasureTrail
                    ) {
                        showTreasureSheet = true
                    }
                    .padding(.horizontal, 12)

                    if let quest = controller.landmarkQuest {
                        LandmarkQuestCard(
                            quest: quest,
                            isVault: treasureStore.weeklyVault.isUnlocked,
                            onFocus: { controller.focusLandmarkQuest() }
                        )
                        .padding(.horizontal, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    MapMissionsStrip(
                        controller: controller,
                        store: store,
                        dailyChallenge: dailyChallenge,
                        onDailyTap: { showDailyChallenge = true },
                        onExpeditionsTap: { showExpeditionSheet = true }
                    )

                    if shouldShowTerritoryCard {
                        TerritoryClaimCard(controller: controller) {
                            showTerritorySheet = true
                        }
                    }

                    IdleScoutsCard(controller: controller) {
                        showIdleScoutsSheet = true
                    }

                    idleBottomSheet
                }
                .padding(.trailing, Self.mapSideControlGutter)
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                Button {
                    withAnimation(AtlasMotion.panel) {
                        isIdleAdventureExpanded = true
                    }
                    AtlasHaptics.select()
                } label: {
                    HStack(spacing: 8) {
                        AtlasArtMark(name: "TreasureCacheMark", size: 28)
                        Text("Adventures")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    GlassChrome(
                        shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                        weight: .regular
                    )
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Show adventures")
                .accessibilityIdentifier("expandAdventuresButton")
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
    }

    private var sharedAdventurePrompt: some View {
        Button {
            showAuthSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(AtlasTheme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock shared treasure")
                        .font(.subheadline.weight(.semibold))
                    Text("Sign in to see nearby community caches and sync this atlas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sharedAdventurePrompt")
    }

    /// Trailing space so expanded adventure cards leave a clear column for map side controls.
    private static let mapSideControlGutter: CGFloat = 70

    private var idleBottomSheet: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(AtlasMotion.panel) {
                    isIdleAdventureExpanded = false
                }
                AtlasHaptics.select()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse adventures")
            .accessibilityIdentifier("collapseAdventuresButton")

            Button {
                showActivityPicker = true
            } label: {
                Label("Track an activity (optional)", systemImage: "figure.walk.motion")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
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

            if controller.isPreparingTreasureTrail {
                AtlasInlineBusyLabel(text: "Scouting landmarks…", tint: AtlasTheme.gold)
                    .padding(.horizontal, 12)
            } else if let target = treasureStore.currentTarget {
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
                .accessibilityLabel("Map layers")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var hasCustomMapPresentation: Bool {
        mapDataLayerRaw != LiveMapDataLayer.mastery.rawValue ||
            !showsMasteryLayer ||
            !showsPlacesLayer ||
            !showsFrontierLayer ||
            !showsFactoryLayer
    }

    private var explorerLevel: Int {
        ExplorerProgressionEngine().level(
            forTotalXP: store.discoveryXPTotal + store.familiarityXPTotal
        )
    }

    private var availableMapDataLayer: LiveMapDataLayer {
        let selected = LiveMapDataLayer(rawValue: mapDataLayerRaw) ?? .mastery
        return selected.requiredLevel <= explorerLevel ? selected : .mastery
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
        guard recorder.lastLocation != nil else { return }
        withAnimation(AtlasMotion.camera) {
            position = .followPuck(
                zoom: controller.isRecording ? 16 : 15,
                pitch: 42
            )
        }
    }

    private func playCameraMoment(_ moment: MapCameraMoment) {
        guard let axial = controller.tileEngine.parseTileID(moment.tileID) else { return }
        followsUser = false
        let destination = Viewport.camera(
            center: controller.tileEngine.centerCoordinate(for: axial),
            zoom: CGFloat(moment.kind.zoom),
            pitch: CGFloat(moment.kind.pitch)
        )
        if reduceMotion {
            position = destination
        } else {
            withViewportAnimation(.fly(duration: moment.kind == .territoryClaim ? 1.75 : 1.35)) {
                position = destination
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        StatsFormat.clockDuration(interval)
    }
}

struct SettingsSheet: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var factoryController: FactoryController
    @Binding var showSimGPSControls: Bool
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(BackgroundRecordingPreference.storageKey) private var backgroundRecordingEnabled = false
    @AppStorage(AutomaticExplorationPreference.backgroundKey) private var automaticBackgroundEnabled = false
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var showingAuth = false

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if auth.session == nil {
                        Label("Guest mode", systemImage: "person.crop.circle.badge.questionmark")
                        Text("Your atlas is saved on this device. Sign in when you want cloud sync or shared treasure.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Sign in to sync") { showingAuth = true }
                    } else {
                        LabeledContent("Signed in as", value: auth.displayName)
                        Button("Sign out") {
                            Task { await auth.signOut() }
                        }
                        Button("Delete account and all progress", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }

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
            .sheet(isPresented: $showingAuth) {
                AuthView(auth: auth)
                    .presentationDetents([.medium, .large])
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settingsDone")
                }
            }
            .confirmationDialog(
                "Delete your Atlasbound account?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete permanently", role: .destructive) {
                    Task { await auth.deleteAccount() }
                }
            } message: {
                Text("This permanently removes your account and all cloud progress.")
            }
        }
    }
}
