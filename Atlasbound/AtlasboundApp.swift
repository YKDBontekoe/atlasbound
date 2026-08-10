import SwiftUI

@main
struct AtlasboundApp: App {
    init() {
        MapboxConfiguration.configure()
    }

    @StateObject private var auth = AuthStore()
    @StateObject private var store = TileStore()
    @StateObject private var activityHistory = ActivityHistoryStore()
    @StateObject private var regionLookup = RegionLookupStore()
    @StateObject private var treasureStore = TreasureStore()
    @StateObject private var inventoryStore = InventoryStore()
    @StateObject private var factoryStore = FactoryStore()
    @StateObject private var idleStore = IdleStore()
    @StateObject private var skillStore = SkillStore()
    @StateObject private var pulseStore = PulseStore()
    @StateObject private var controllerHolder = ControllerHolder()
    @StateObject private var factoryHolder = FactoryHolder()
    @StateObject private var cloudStateSync = CloudStateSync()
    @State private var cloudBootstrapStarted = false
    @State private var cloudBootstrapError: String?
    @State private var cloudBootstrapTask: Task<Void, Never>?
    @State private var accountTransitionUserID: UUID?
    @State private var accountTransitionCheckedUserID: UUID?
    @State private var showAuthSheet = false
    @AppStorage(WelcomePreference.completedKey) private var welcomeCompleted = false
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue

    private var isUITestMode: Bool {
        ProcessInfo.processInfo.environment["ATLASBOUND_UI_TEST_MODE"] == "1"
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading && !isUITestMode {
                    LoadingWorldView()
                } else if accountTransitionUserID != nil && !isUITestMode {
                    AccountTransitionView(
                        chooseCloud: { finishAccountTransition(.cloud) },
                        chooseDevice: { finishAccountTransition(.device) },
                        cancel: { cancelAccountTransition() }
                    )
                } else if auth.session == nil && !welcomeCompleted && !isUITestMode {
                    GuestWelcomeView(
                        startExploring: startGuestExperience,
                        signIn: { showAuthSheet = true }
                    )
                } else if auth.needsProfileSetup && !isUITestMode {
                    ProfileSetupView(auth: auth)
                } else if let cloudBootstrapError, !isUITestMode {
                    CloudBootstrapErrorView(message: cloudBootstrapError) {
                        retryCloudBootstrap()
                    }
                } else if let controller = controllerHolder.controller,
                   let factoryController = factoryHolder.controller {
                    RootTabView(
                        auth: auth,
                        controller: controller,
                        store: store,
                        activityHistory: activityHistory,
                        regionLookup: regionLookup,
                        factoryController: factoryController
                    )
                } else {
                    LoadingWorldView()
                }
            }
            .preferredColorScheme(
                AppearancePreference(rawValue: appearanceRaw)?.preferredColorScheme
            )
            .onAppear {
                let sessionStore = store
                let sessionActivityHistory = activityHistory
                let sessionRegionLookup = regionLookup
                let sessionTreasure = treasureStore
                let sessionInventory = inventoryStore
                let sessionFactory = factoryStore
                let sessionIdle = idleStore
                let sessionSkills = skillStore
                let sessionPulses = pulseStore
                let sessionCloudSync = cloudStateSync
                let sessionAuth = auth
                auth.onSessionEnded = { @MainActor in
                    sessionCloudSync.stop()
                    guard !sessionAuth.preserveLocalStateOnSignOut else {
                        return
                    }
                    sessionStore.resetLocalSession()
                    sessionActivityHistory.resetLocalSession()
                    sessionRegionLookup.resetLocalSession()
                    sessionTreasure.resetLocalSession()
                    sessionInventory.resetLocalSession()
                    sessionFactory.resetLocalSession()
                    sessionIdle.resetLocalSession()
                    sessionSkills.resetLocalSession()
                    sessionPulses.resetLocalSession()
                }
                bootstrapWorldIfAuthenticated()
            }
            .onChange(of: auth.session?.user.id) { oldValue, newValue in
                guard oldValue != newValue else { return }
                if newValue == nil {
                    if auth.preserveLocalStateOnSignOut {
                        auth.preserveLocalStateOnSignOut = false
                    } else {
                        resetLocalSession()
                    }
                } else if oldValue != nil {
                    resetLocalSession()
                    accountTransitionUserID = nil
                }
                if newValue != nil {
                    bootstrapWorldIfAuthenticated()
                }
            }
            .onOpenURL { url in
                Task { await auth.handle(url: url) }
            }
            .sheet(isPresented: $showAuthSheet) {
                AuthView(auth: auth)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @MainActor
    private func bootstrapWorldIfAuthenticated() {
        guard auth.session != nil || isUITestMode || welcomeCompleted else { return }
        guard !cloudBootstrapStarted else { return }
        cloudBootstrapStarted = true
        cloudBootstrapError = nil
        let startingUserID = auth.session?.user.id
        let authStore = auth
        cloudBootstrapTask = Task { @MainActor in
            if let startingUserID {
                let isSessionActive: @MainActor () -> Bool = {
                    authStore.session?.user.id == startingUserID
                }
                if accountTransitionCheckedUserID != startingUserID,
                   store.hasLocalProgress {
                    let hasRemoteCloud = await store.hasRemoteCloudRecord()
                    let hasRemoteState = hasRemoteCloud
                        ? true
                        : await cloudStateSync.hasRemoteState()
                    let hasRemote = hasRemoteCloud || hasRemoteState
                    guard !Task.isCancelled, isSessionActive() else { return }
                    if hasRemote {
                        accountTransitionUserID = startingUserID
                        cloudBootstrapStarted = false
                        return
                    }
                    accountTransitionCheckedUserID = startingUserID
                }
                guard await store.hydrateFromCloud(isSessionActive: isSessionActive) else {
                    guard !Task.isCancelled, isSessionActive() else { return }
                    failCloudBootstrap()
                    return
                }
                guard !Task.isCancelled, isSessionActive() else { return }
                guard await cloudStateSync.hydrate(
                    activityHistory: activityHistory,
                    regionLookup: regionLookup,
                    treasure: treasureStore,
                    inventory: inventoryStore,
                    factory: factoryStore,
                    idle: idleStore,
                    skills: skillStore,
                    pulse: pulseStore,
                    isSessionActive: isSessionActive
                ) else {
                    guard !Task.isCancelled, isSessionActive() else { return }
                    failCloudBootstrap()
                    return
                }
            }
            guard !Task.isCancelled,
                  startingUserID == nil || authStore.session?.user.id == startingUserID
            else { return }
            bootstrapControllers()
        }
    }

    private enum AccountTransitionChoice { case cloud, device }

    private func startGuestExperience() {
        welcomeCompleted = true
        UserDefaults.standard.set(true, forKey: WelcomePreference.explorationStartedKey)
        showAuthSheet = false
        bootstrapWorldIfAuthenticated()
    }

    @MainActor
    private func finishAccountTransition(_ choice: AccountTransitionChoice) {
        guard let userID = accountTransitionUserID,
              auth.session?.user.id == userID else { return }
        accountTransitionUserID = nil
        if choice == .cloud {
            accountTransitionCheckedUserID = userID
            resetLocalSession()
            accountTransitionUserID = nil
            cloudBootstrapStarted = false
            bootstrapWorldIfAuthenticated()
        } else {
            accountTransitionCheckedUserID = userID
            accountTransitionUserID = nil
            cloudBootstrapStarted = true
            bootstrapControllers()
            store.queueFullCloudUpload()
            Task {
                await cloudStateSync.syncNow(
                    tileStore: store,
                    activityHistory: activityHistory,
                    regionLookup: regionLookup,
                    treasure: treasureStore,
                    inventory: inventoryStore,
                    factory: factoryStore,
                    idle: idleStore,
                    skills: skillStore,
                    pulse: pulseStore
                )
            }
        }
    }

    @MainActor
    private func cancelAccountTransition() {
        auth.preserveLocalStateOnSignOut = true
        Task { await auth.signOut() }
        accountTransitionUserID = nil
        cloudBootstrapStarted = false
        accountTransitionCheckedUserID = nil
    }

    @MainActor
    private func failCloudBootstrap() {
        cloudBootstrapStarted = false
        cloudBootstrapError = "Your local atlas is safe, but cloud sync did not finish. Check your connection and try again."
    }

    @MainActor
    private func retryCloudBootstrap() {
        cloudBootstrapError = nil
        cloudBootstrapStarted = false
        bootstrapWorldIfAuthenticated()
    }

    @MainActor
    private func bootstrapControllers() {
        if auth.session != nil {
            UserDefaults.standard.set(true, forKey: WelcomePreference.explorationStartedKey)
        }
        controllerHolder.bootstrap(
            store: store,
            activityHistory: activityHistory,
            regionLookup: regionLookup,
            treasureStore: treasureStore,
            inventoryStore: inventoryStore,
            idleStore: idleStore,
            skillStore: skillStore,
            pulseStore: pulseStore
        )
        factoryHolder.bootstrap(
            store: factoryStore,
            tileStore: store,
            inventoryStore: inventoryStore,
            skillStore: skillStore
        )
        if auth.session != nil {
            cloudStateSync.start(
                tileStore: store,
                activityHistory: activityHistory,
                regionLookup: regionLookup,
                treasure: treasureStore,
                inventory: inventoryStore,
                factory: factoryStore,
                idle: idleStore,
                skills: skillStore,
                pulse: pulseStore
            )
        }
    }

    @MainActor
    private func resetLocalSession() {
        cloudBootstrapTask?.cancel()
        cloudBootstrapTask = nil
        cloudStateSync.stop()
        store.resetLocalSession()
        activityHistory.resetLocalSession()
        regionLookup.resetLocalSession()
        treasureStore.resetLocalSession()
        inventoryStore.resetLocalSession()
        factoryStore.resetLocalSession()
        idleStore.resetLocalSession()
        skillStore.resetLocalSession()
        pulseStore.resetLocalSession()
        controllerHolder.reset()
        factoryHolder.reset()
        cloudBootstrapStarted = false
        cloudBootstrapError = nil
    }
}

@MainActor
final class FactoryHolder: ObservableObject {
    @Published var controller: FactoryController?

    func reset() {
        controller = nil
    }

    func bootstrap(
        store: FactoryStore,
        tileStore: TileStore,
        inventoryStore: InventoryStore,
        skillStore: SkillStore
    ) {
        guard controller == nil else { return }
        controller = FactoryController(
            store: store,
            tileStore: tileStore,
            inventoryStore: inventoryStore,
            skillStore: skillStore
        )
        controller?.advance()
    }
}

@MainActor
final class ControllerHolder: ObservableObject {
    @Published var controller: WorldController?

    func reset() {
        controller = nil
    }

    func bootstrap(
        store: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore,
        treasureStore: TreasureStore,
        inventoryStore: InventoryStore,
        idleStore: IdleStore,
        skillStore: SkillStore,
        pulseStore: PulseStore
    ) {
        guard controller == nil else { return }
        controller = WorldController(
            store: store,
            activityHistory: activityHistory,
            regionLookup: regionLookup,
            treasureStore: treasureStore,
            inventoryStore: inventoryStore,
            idleStore: idleStore,
            skillStore: skillStore,
            pulseStore: pulseStore
        )
    }
}
