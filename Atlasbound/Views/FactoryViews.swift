import SwiftUI

struct FactoryTabView: View {
    @ObservedObject var controller: FactoryController

    var body: some View {
        NavigationStack {
            FactoryHubView(controller: controller)
                .navigationTitle("Factory")
        }
    }
}

struct FactoryHubView: View {
    @ObservedObject var controller: FactoryController
    @ObservedObject private var store: FactoryStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(FactoryTutorialPreference.storageKey) private var tutorialVersion = 0
    @State private var showsTutorial = false
    @State private var showsHelp = false
    @State private var replaysTutorialAfterHelp = false

    init(controller: FactoryController) {
        self.controller = controller
        self._store = ObservedObject(wrappedValue: controller.store)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AtlasTheme.Space.lg) {
                heroCard
                    .staggeredAppear(index: 0)

                if let message = controller.latestMessage {
                    StatSectionCard {
                        FactoryMessageBanner(message: message) {
                            controller.latestMessage = nil
                        }
                    }
                    .staggeredAppear(index: 1)
                }

                overviewCard
                    .staggeredAppear(index: 2)
                manageCard
                    .staggeredAppear(index: 3)
                networksCard
                    .staggeredAppear(index: 4)

                if !store.lifetimeProduced.isEmpty {
                    ledgerCard
                        .staggeredAppear(index: 5)
                }
            }
            .padding(AtlasTheme.Space.xl)
        }
        .background(AtlasTheme.canvas(for: colorScheme))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Factory help")
                .accessibilityHint("Opens the quick start guide and status explanations.")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    controller.advance()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh factory")
                .accessibilityHint("Advances production to the current time and refreshes all factory statuses.")
            }
        }
        .sheet(isPresented: $showsHelp, onDismiss: {
            if replaysTutorialAfterHelp {
                replaysTutorialAfterHelp = false
                showsTutorial = true
            }
        }) {
            FactoryHelpSheet {
                replaysTutorialAfterHelp = true
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showsTutorial) {
            FactoryTutorialView {
                tutorialVersion = FactoryTutorialPreference.currentVersion
                showsTutorial = false
            }
        }
        .task {
            if tutorialVersion < FactoryTutorialPreference.currentVersion {
                showsTutorial = true
            }
            controller.advance()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                controller.advance()
            }
        }
    }

    private var heroCard: some View {
        StatSectionCard {
            HStack(spacing: AtlasTheme.Space.lg) {
                AtlasArtMark(name: "FactoryMark", size: 72)
                VStack(alignment: .leading, spacing: AtlasTheme.Space.xs) {
                    Text("Build an outpost")
                        .font(.headline)
                    Text("Link nearby structures into a working network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var overviewCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Factory overview",
                    subtitle: "Structures, power, and lifetime production.",
                    systemImage: "building.2.fill",
                    accent: AtlasTheme.blue
                )

                AtlasMetricRow(
                    label: "Structures",
                    value: "\(controller.structures.count)",
                    systemImage: "cube.fill"
                )
                AtlasMetricRow(
                    label: "Road networks",
                    value: "\(controller.networks.count)",
                    systemImage: "road.lanes"
                )
                AtlasMetricRow(
                    label: "Power",
                    value: "\(controller.totalPowerDemand) / \(controller.totalPowerSupply)",
                    valueColor: controller.totalPowerDemand > controller.totalPowerSupply
                        ? AtlasTheme.finishRed
                        : .primary,
                    systemImage: "bolt.fill"
                )
                AtlasMetricRow(
                    label: "Lifetime output",
                    value: "\(store.lifetimeProduced.values.reduce(0, +)) items",
                    systemImage: "chart.bar.fill"
                )

                if controller.totalPowerDemand > controller.totalPowerSupply {
                    Label("Power demand exceeds supply", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtlasTheme.gold)
                }

                let blocked = controller.structures.filter {
                    ![FactoryOperationalStatus.running, .idle].contains(controller.status(for: $0))
                }
                if !blocked.isEmpty {
                    AtlasMetricRow(
                        label: "Needs attention",
                        value: "\(blocked.count)",
                        valueColor: AtlasTheme.finishRed,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }
            }
        }
    }

    private var manageCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Manage",
                    subtitle: "Collect output, research, and inspect structures.",
                    systemImage: "slider.horizontal.3",
                    accent: AtlasTheme.teal
                )

                Button {
                    _ = controller.remoteCollectAllDepots()
                } label: {
                    AtlasChromeLinkRow(
                        title: controller.remoteCollectableItemCount > 0
                            ? "Remote collect (\(controller.remoteCollectableItemCount))"
                            : "Remote collect",
                        systemImage: "shippingbox.and.arrow.backward.fill",
                        subtitle: controller.remoteCollectableItemCount > 0
                            ? "Pull depot output into your pack."
                            : "No depot goods ready to collect.",
                        accent: AtlasTheme.teal,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(controller.remoteCollectableItemCount == 0)
                .opacity(controller.remoteCollectableItemCount == 0 ? 0.45 : 1)
                .accessibilityIdentifier("remoteCollectDepotsButton")

                Divider().overlay(AtlasTheme.divider(for: colorScheme))

                NavigationLink {
                    FactoryRecipeBookView(controller: controller)
                } label: {
                    AtlasChromeLinkRow(
                        title: "Recipe book",
                        systemImage: "book.pages.fill",
                        subtitle: "Hand assembly and machine recipes.",
                        accent: AtlasTheme.blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    FactoryResearchView(controller: controller)
                } label: {
                    AtlasChromeLinkRow(
                        title: "Research",
                        systemImage: "lightbulb.max.fill",
                        subtitle: "Spend atlas insight to unlock machines.",
                        accent: AtlasTheme.gold
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    FactoryStructureListView(controller: controller)
                } label: {
                    AtlasChromeLinkRow(
                        title: "Structures",
                        systemImage: "building.2.fill",
                        subtitle: "Inspect buffers and production status.",
                        accent: AtlasTheme.blue
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var networksCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Networks",
                    subtitle: "Road-linked clusters that share power and logistics.",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    accent: AtlasTheme.teal
                )

                if controller.networks.isEmpty {
                    AtlasEmptyState(
                        title: "No road networks",
                        message: "Craft road kits in the Recipe book, then place them from the Map while standing nearby.",
                        systemImage: "road.lanes",
                        artName: "FactoryMark",
                        accent: AtlasTheme.teal
                    )
                } else {
                    ForEach(Array(controller.networks.enumerated()), id: \.element.id) { index, network in
                        if index > 0 {
                            Divider().overlay(AtlasTheme.divider(for: colorScheme))
                        }
                        let metrics = controller.networkMetrics.first { $0.networkID == network.id }
                        VStack(alignment: .leading, spacing: AtlasTheme.Space.xs) {
                            Text("Network \(network.id)")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(network.roadTileIDs.count) roads · \(network.buildingTileIDs.count) buildings · \(network.totalRoadCapacity) item-units/min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let metrics {
                                Text("Power \(metrics.powerDemand)/\(metrics.powerSupply) · \(metrics.storedItemCount) stored items")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(
                                        metrics.powerDemand > metrics.powerSupply
                                            ? AtlasTheme.finishRed
                                            : AtlasTheme.teal
                                    )
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Road network \(network.id)")
                        .accessibilityValue(networkAccessibilityValue(network, metrics: metrics))
                    }
                }
            }
        }
    }

    private var ledgerCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Production ledger",
                    subtitle: "Lifetime items produced across all machines.",
                    systemImage: "list.bullet.rectangle",
                    accent: AtlasTheme.slate
                )

                ForEach(Array(store.lifetimeProduced.keys.sorted().enumerated()), id: \.element) { index, itemID in
                    if index > 0 {
                        Divider().overlay(AtlasTheme.divider(for: colorScheme))
                    }
                    AtlasMetricRow(
                        label: ItemCatalog.definition(for: itemID)?.name ?? itemID,
                        value: "\(store.lifetimeProduced[itemID] ?? 0)"
                    )
                }
            }
        }
    }

    private func networkAccessibilityValue(
        _ network: FactoryNetworkSnapshot,
        metrics: FactoryNetworkMetrics?
    ) -> String {
        var parts = [
            "\(network.roadTileIDs.count) roads",
            "\(network.buildingTileIDs.count) buildings",
            "capacity \(network.totalRoadCapacity) item units per minute",
        ]
        if let metrics {
            parts.append("power demand \(metrics.powerDemand) of \(metrics.powerSupply)")
            parts.append("\(metrics.storedItemCount) stored items")
        }
        return parts.joined(separator: ", ")
    }
}

struct FactoryBuildCatalogSheet: View {
    @ObservedObject var controller: FactoryController
    @ObservedObject private var inventory: InventoryStore
    let onSelected: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(controller: FactoryController, onSelected: @escaping () -> Void) {
        self.controller = controller
        self._inventory = ObservedObject(wrappedValue: controller.inventoryStore)
        self.onSelected = onSelected
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a kit, then tap a discovered hex while standing on or beside it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Roads and buildings") {
                    ForEach(FactoryCatalog.definitions) { definition in
                        let unlocked = definition.requiredResearchID.map(controller.store.unlockedResearchIDs.contains) ?? true
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: definition.symbolName)
                                    .foregroundStyle(unlocked ? AtlasTheme.gold : .secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(definition.name).font(.subheadline.weight(.semibold))
                                    Text(definition.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("×\(inventory.quantity(of: definition.kitItemID))")
                                    .font(.subheadline.weight(.bold))
                            }

                            HStack {
                                if let recipe = ItemRecipes.all.first(where: { $0.primaryOutput?.itemID == definition.kitItemID }),
                                   recipe.isHandCraftable,
                                   inventory.canConsume(recipe.inputs) {
                                    Button("Craft kit") {
                                        _ = inventory.assemble(recipeID: recipe.id)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Spacer()
                                Button("Build") {
                                    controller.selectBuildDefinition(definition.id)
                                    onSelected()
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AtlasTheme.teal)
                                .disabled(!unlocked)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(definition.name)
                        .accessibilityValue(
                            "\(inventory.quantity(of: definition.kitItemID)) kits available. "
                                + (unlocked ? "Unlocked." : "Locked.")
                        )
                        .accessibilityHint(
                            unlocked
                                ? "Craft a kit if materials are available, or choose Build to enter map construction mode."
                                : "Unlock the required research before building."
                        )
                    }
                }
            }
            .navigationTitle("Construction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct FactoryRecipeBookView: View {
    @ObservedObject var controller: FactoryController
    @ObservedObject private var inventory: InventoryStore

    init(controller: FactoryController) {
        self.controller = controller
        self._inventory = ObservedObject(wrappedValue: controller.inventoryStore)
    }

    var body: some View {
        List {
            Section("Hand assembly") {
                ForEach(ItemRecipes.all.filter(\.isHandCraftable)) { recipe in
                    recipeRow(recipe)
                }
            }
            Section("Automated production") {
                ForEach(FactoryRecipeCatalog.machineRecipes) { recipe in
                    recipeRow(recipe)
                }
            }
        }
        .navigationTitle("Recipe Book")
    }

    private func recipeRow(_ recipe: RecipeDefinition) -> some View {
        let unlocked = recipe.requiredResearchID.map(controller.store.unlockedResearchIDs.contains) ?? true
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(recipe.displayName).font(.subheadline.weight(.semibold))
                Spacer()
                if recipe.durationMinutes > 0 {
                    Text("\(recipe.durationMinutes)m").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("In: \(amountLabel(recipe.inputs))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Out: \(amountLabel(recipe.outputs))")
                .font(.caption)
                .foregroundStyle(AtlasTheme.teal)
            if !unlocked, let researchID = recipe.requiredResearchID {
                Label(
                    "Requires \(FactoryResearchCatalog.byID[researchID]?.name ?? "research")",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if recipe.isHandCraftable {
                if !inventory.canConsume(recipe.inputs) {
                    Text("Missing: \(missingInputLabel(recipe.inputs))")
                        .font(.caption2)
                        .foregroundStyle(AtlasTheme.finishRed)
                }
                Button("Assemble") {
                    _ = inventory.assemble(recipeID: recipe.id)
                }
                .buttonStyle(.bordered)
                .disabled(!inventory.canConsume(recipe.inputs))
                .accessibilityLabel("Assemble \(recipe.displayName)")
                .accessibilityHint(
                    inventory.canConsume(recipe.inputs)
                        ? "Consumes the listed inputs and adds all outputs to your backpack."
                        : "Unavailable. Missing \(missingInputLabel(recipe.inputs))."
                )
            } else {
                Text("Crafter: \(recipe.producerIDs.compactMap { FactoryCatalog.byID[$0]?.name }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(recipe.displayName)
        .accessibilityValue(
            "Inputs \(amountLabel(recipe.inputs)). Outputs \(amountLabel(recipe.outputs)). "
                + (recipe.durationMinutes > 0 ? "Duration \(recipe.durationMinutes) minutes." : "")
        )
    }

    private func missingInputLabel(_ inputs: [ItemAmount]) -> String {
        inputs.compactMap { amount in
            let missing = max(0, amount.quantity - inventory.quantity(of: amount.itemID))
            guard missing > 0 else { return nil }
            return "\(missing) \(ItemCatalog.definition(for: amount.itemID)?.name ?? amount.itemID)"
        }
        .joined(separator: ", ")
    }
}

struct FactoryResearchView: View {
    @ObservedObject var controller: FactoryController
    @ObservedObject private var store: FactoryStore

    init(controller: FactoryController) {
        self.controller = controller
        self._store = ObservedObject(wrappedValue: controller.store)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Explorer level", value: "\(controller.explorerLevel)")
                LabeledContent("Available insights", value: "\(controller.availableItemCount("atlas_insight"))")
            }
            if let message = controller.latestMessage {
                Section {
                    FactoryMessageBanner(message: message) {
                        controller.latestMessage = nil
                    }
                }
            }
            Section("Research tree") {
                ForEach(FactoryResearchCatalog.all) { research in
                    let unlocked = store.unlockedResearchIDs.contains(research.id)
                    let prerequisitesMet = research.prerequisiteIDs.isSubset(of: store.unlockedResearchIDs)
                    let insightCost = controller.effectiveInsightCost(for: research)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: unlocked ? "checkmark.seal.fill" : "lightbulb.max")
                                .foregroundStyle(unlocked ? AtlasTheme.teal : AtlasTheme.gold)
                            Text(research.name).font(.headline)
                            Spacer()
                            Text(unlocked ? "Unlocked" : "\(insightCost) Insight")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(research.detail).font(.caption).foregroundStyle(.secondary)
                        if !unlocked {
                            Text("Explorer level \(research.explorerLevel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let blockedReason = researchBlockedReason(
                                research,
                                prerequisitesMet: prerequisitesMet,
                                insightCost: insightCost
                            ) {
                                Label(blockedReason, systemImage: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AtlasTheme.finishRed)
                            }
                            Button("Research") {
                                _ = controller.unlockResearch(research.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                !prerequisitesMet
                                    || controller.explorerLevel < research.explorerLevel
                                    || controller.availableItemCount("atlas_insight") < insightCost
                            )
                            .accessibilityLabel("Research \(research.name)")
                            .accessibilityHint(
                                researchBlockedReason(
                                    research,
                                    prerequisitesMet: prerequisitesMet,
                                    insightCost: insightCost
                                )
                                    ?? "Spends \(insightCost) Atlas Insight and unlocks \(research.name)."
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .navigationTitle("Research")
    }

    private func researchBlockedReason(
        _ research: FactoryResearchDefinition,
        prerequisitesMet: Bool,
        insightCost: Int
    ) -> String? {
        if !prerequisitesMet {
            let missing = research.prerequisiteIDs
                .subtracting(store.unlockedResearchIDs)
                .compactMap { FactoryResearchCatalog.byID[$0]?.name }
                .sorted()
            return "Requires \(missing.joined(separator: ", "))"
        }
        if controller.explorerLevel < research.explorerLevel {
            return "Requires Explorer level \(research.explorerLevel)"
        }
        let available = controller.availableItemCount("atlas_insight")
        if available < insightCost {
            return "Requires \(insightCost - available) more Atlas Insight"
        }
        return nil
    }
}

struct FactoryStructureListView: View {
    @ObservedObject var controller: FactoryController
    @ObservedObject private var store: FactoryStore

    init(controller: FactoryController) {
        self.controller = controller
        self._store = ObservedObject(wrappedValue: controller.store)
    }

    var body: some View {
        List {
            if controller.structures.isEmpty {
                ContentUnavailableView(
                    "No structures",
                    systemImage: "building.2",
                    description: Text("Place your first road and building from the Map.")
                )
            } else {
                ForEach(controller.structures) { structure in
                    NavigationLink {
                        FactoryStructureInspector(controller: controller, tileID: structure.tileID)
                    } label: {
                        let definition = FactoryCatalog.byID[structure.definitionID]
                        let status = controller.status(for: structure)
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(definition?.name ?? structure.definitionID)
                                Text("\(status.displayName) · \(structure.tileID)")
                                    .font(.caption2)
                                    .foregroundStyle(status == .running ? .secondary : AtlasTheme.gold)
                            }
                        } icon: {
                            Image(systemName: definition?.symbolName ?? "questionmark")
                                .foregroundStyle(AtlasTheme.gold)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(definition?.name ?? structure.definitionID)
                        .accessibilityValue("\(status.displayName), tile \(structure.tileID)")
                        .accessibilityHint("Opens structure details.")
                    }
                }
            }
        }
        .navigationTitle("Structures")
    }
}

struct FactoryStructureInspector: View {
    @ObservedObject var controller: FactoryController
    @ObservedObject private var store: FactoryStore
    @ObservedObject private var inventory: InventoryStore
    let tileID: String
    @State private var confirmsDemolition = false
    @Environment(\.dismiss) private var dismiss

    init(controller: FactoryController, tileID: String) {
        self.controller = controller
        self.tileID = tileID
        self._store = ObservedObject(wrappedValue: controller.store)
        self._inventory = ObservedObject(wrappedValue: controller.inventoryStore)
    }

    var body: some View {
        NavigationStack {
            List {
                if let structure = store.structures[tileID],
                   let definition = FactoryCatalog.byID[structure.definitionID] {
                    if let message = controller.latestMessage {
                        Section {
                            FactoryMessageBanner(message: message) {
                                controller.latestMessage = nil
                            }
                        }
                    }
                    Section {
                        Label(definition.name, systemImage: definition.symbolName)
                            .font(.headline)
                        Text(definition.detail).font(.footnote).foregroundStyle(.secondary)
                        LabeledContent("Tile", value: tileID)
                        LabeledContent("Tier", value: "\(structure.tier)")
                        LabeledContent("Status", value: controller.status(for: structure).displayName)
                        if definition.kind == .extractor {
                            let deposit = ConstructionEngine().deposit(for: tileID)
                            LabeledContent("Deposit", value: deposit.kind.displayName)
                            LabeledContent("Remaining", value: "\(max(0, deposit.capacity - structure.extractedUnits))")
                        }
                    }

                    if !definition.allowedRecipeIDs.isEmpty {
                        Section("Production") {
                            Picker(
                                "Recipe",
                                selection: Binding(
                                    get: { structure.selectedRecipeID },
                                    set: { controller.selectRecipe($0, for: tileID) }
                                )
                            ) {
                                Text("Paused").tag(String?.none)
                                ForEach(definition.allowedRecipeIDs, id: \.self) { recipeID in
                                    Text(FactoryRecipeCatalog.byID[recipeID]?.displayName ?? recipeID)
                                        .tag(String?.some(recipeID))
                                }
                            }
                            Picker(
                                "Power priority",
                                selection: Binding(
                                    get: { structure.priority },
                                    set: { controller.setPriority($0, for: tileID) }
                                )
                            ) {
                                ForEach(FactoryPriority.allCases, id: \.self) {
                                    Text($0.displayName).tag($0)
                                }
                            }
                            if let recipeID = structure.selectedRecipeID,
                               let recipe = FactoryRecipeCatalog.byID[recipeID] {
                                ProgressView(
                                    value: Double(structure.recipeProgressMinutes),
                                    total: Double(max(1, recipe.durationMinutes))
                                )
                                .accessibilityLabel("\(recipe.displayName) cycle progress")
                                .accessibilityValue(
                                    "\(structure.recipeProgressMinutes) of \(recipe.durationMinutes) minutes"
                                )
                            }
                        }
                    }

                    bufferSection(
                        "Input buffer",
                        buffer: structure.inputBuffer,
                        allowsWithdraw: true,
                        isInputBuffer: true
                    )
                    bufferSection(
                        definition.kind == .depot ? "Stored goods" : "Output buffer",
                        buffer: structure.outputBuffer,
                        allowsWithdraw: true,
                        isInputBuffer: false
                    )

                    if definition.kind == .depot
                        || definition.kind == .generator
                        || definition.kind == .processor
                        || definition.kind == .research {
                        Section("Load from backpack") {
                            let transferable = inventory.sortedStacks.filter {
                                $0.quantity > 0
                                    && controller.canManuallyLoad(itemID: $0.itemID, into: definition)
                            }
                            if transferable.isEmpty {
                                Text("No transferable items").foregroundStyle(.secondary)
                            } else {
                                ForEach(transferable) { stack in
                                    HStack {
                                        Text(ItemCatalog.definition(for: stack.itemID)?.name ?? stack.itemID)
                                        Spacer()
                                        Text("×\(stack.quantity)").foregroundStyle(.secondary)
                                        Button("Load 1") {
                                            _ = controller.deposit(itemID: stack.itemID, quantity: 1, into: tileID)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(
                                            "Load one \(ItemCatalog.definition(for: stack.itemID)?.name ?? stack.itemID)"
                                        )
                                        .accessibilityHint("Moves one item from your backpack into this structure.")
                                    }
                                }
                            }
                        }
                    }

                    Section("Actions") {
                        if (definition.kind == .extractor && store.unlockedResearchIDs.contains("extraction_2"))
                            || (definition.kind == .generator && store.unlockedResearchIDs.contains("power_2")) {
                            Button("Upgrade to tier 2") {
                                _ = controller.upgradeStructure(at: tileID)
                            }
                            .disabled(structure.tier >= 2)
                        }
                        Button("Dismantle", role: .destructive) {
                            confirmsDemolition = true
                        }
                    }
                } else {
                    ContentUnavailableView("Structure missing", systemImage: "questionmark.folder")
                }
            }
            .navigationTitle("Structure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Dismantle this structure?",
                isPresented: $confirmsDemolition,
                titleVisibility: .visible
            ) {
                Button("Dismantle", role: .destructive) {
                    if controller.demolish(at: tileID) {
                        dismiss()
                    }
                }
            } message: {
                Text("Buffers must be empty. Half of the construction materials will be returned.")
            }
        }
    }

    @ViewBuilder
    private func bufferSection(
        _ title: String,
        buffer: [String: Int],
        allowsWithdraw: Bool,
        isInputBuffer: Bool
    ) -> some View {
        Section(title) {
            if buffer.isEmpty {
                Text("Empty").foregroundStyle(.secondary)
            } else {
                ForEach(buffer.keys.sorted(), id: \.self) { itemID in
                    HStack {
                        Text(ItemCatalog.definition(for: itemID)?.name ?? itemID)
                        Spacer()
                        Text("×\(buffer[itemID] ?? 0)")
                        if allowsWithdraw {
                            Button {
                                _ = controller.withdraw(
                                    itemID: itemID,
                                    quantity: 1,
                                    from: tileID,
                                    inputBuffer: isInputBuffer
                                )
                            } label: {
                                Image(systemName: "backpack.fill")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                "Withdraw one \(ItemCatalog.definition(for: itemID)?.name ?? itemID)"
                            )
                            .accessibilityHint("Moves one item from this structure to your backpack.")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Factory message")
    }
}

private func amountLabel(_ amounts: [ItemAmount]) -> String {
    amounts.map {
        "\(ItemCatalog.definition(for: $0.itemID)?.name ?? $0.itemID) ×\($0.quantity)"
    }.joined(separator: " · ")
}

private struct FactoryMessageBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape.fill")
                .foregroundStyle(AtlasTheme.gold)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss factory message")
        }
    }
}
