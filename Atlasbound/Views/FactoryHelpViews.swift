import SwiftUI

enum FactoryTutorialPreference {
    static let storageKey = "atlasbound.factoryTutorialVersion"
    static let currentVersion = 1
}

struct FactoryTutorialView: View {
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleIsFocused: Bool
    @State private var step = 0

    private let steps: [(icon: String, title: String, body: String, tip: String)] = [
        (
            "map.fill",
            "Reveal local resources",
            "Explore a hex, then revisit it to reveal its deposit. Deposits are generated from the hex and stay the same.",
            "Resource markers appear while construction mode is open."
        ),
        (
            "shippingbox.fill",
            "Assemble construction kits",
            "Open Workshop → Factory → Recipe book. Hand-assemble a road or building kit from materials in your backpack.",
            "Every placement consumes one matching kit."
        ),
        (
            "figure.walk",
            "Build while nearby",
            "On the Map, tap the hammer, choose a kit, then tap your current or an adjacent discovered hex.",
            "The preview explains exactly why a placement is ready or blocked."
        ),
        (
            "point.3.connected.trianglepath.dotted",
            "Connect and power",
            "Place roads beside buildings, add a depot for storage, and load Amber Resin into a Waystone Dynamo.",
            "A building can exist while disconnected, but it will remain inactive."
        ),
        (
            "gearshape.2.fill",
            "Automate and research",
            "Choose recipes in structure details, set power priorities, and spend Atlas Insight to unlock better logistics.",
            "You can monitor and manage recipes remotely; building and item transfers require proximity."
        ),
    ]

    var body: some View {
        ZStack {
            AtlasTheme.canvas(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    Text("Factory guide")
                        .font(.headline)
                    Spacer()
                    Button("Skip") {
                        onComplete()
                    }
                    .accessibilityHint("Closes the guide. You can reopen it from Factory Help.")
                }
                .padding(.horizontal, 24)

                ScrollView {
                    VStack(spacing: 18) {
                        Image(systemName: steps[step].icon)
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AtlasTheme.gold, AtlasTheme.teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .accessibilityHidden(true)

                        Text(steps[step].title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .accessibilityFocused($titleIsFocused)

                        Text(steps[step].body)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Label(steps[step].tip, systemImage: "info.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background {
                        GlassChrome(
                            shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                            weight: .regular
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }

                HStack(spacing: 8) {
                    ForEach(steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? AtlasTheme.gold : Color.secondary.opacity(0.35))
                            .frame(width: index == step ? 22 : 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Tutorial progress")
                .accessibilityValue("Step \(step + 1) of \(steps.count)")

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Back") {
                            move(to: step - 1)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(step == steps.count - 1 ? "Start building" : "Next") {
                        if step == steps.count - 1 {
                            AtlasHaptics.success()
                            onComplete()
                        } else {
                            move(to: step + 1)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.teal)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint(
                        step == steps.count - 1
                            ? "Closes the guide and opens the Factory overview."
                            : "Shows the next Factory guide step."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .accessibilityIdentifier("factoryTutorial")
        .onAppear {
            titleIsFocused = true
        }
    }

    private func move(to newStep: Int) {
        AtlasHaptics.select()
        titleIsFocused = false
        AtlasMotion.withOptionalAnimation(AtlasMotion.chrome, reduceMotion: reduceMotion) {
            step = newStep
        }
        Task { @MainActor in
            titleIsFocused = true
        }
    }
}

struct FactoryHelpSheet: View {
    let onReplayTutorial: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Quick start") {
                    helpRow("1", "Explore and revisit", "Revisit an explored hex to reveal its resource.")
                    helpRow("2", "Craft a kit", "In Workshop, open Recipe book (Journal or Factory) to hand-assemble roads and starter buildings.")
                    helpRow("3", "Build nearby", "On the Map, tap the hammer and select your current or an adjacent hex.")
                    helpRow("4", "Connect the network", "Put roads beside buildings. Add a fueled dynamo and a depot.")
                    helpRow("5", "Choose a recipe", "Open Structures, select a production recipe, and check its status.")
                }

                Section("Status guide") {
                    statusRow("Running", "gearshape.2.fill", AtlasTheme.teal, "The building is working this minute.")
                    statusRow("Idle", "pause.circle.fill", AtlasTheme.gold, "No recipe is selected, or there is currently no work.")
                    statusRow("Disconnected", "point.3.filled.connected.trianglepath.dotted", AtlasTheme.finishRed, "Place a road on an adjacent hex.")
                    statusRow("No power", "bolt.slash.fill", AtlasTheme.finishRed, "Add or fuel a dynamo, or raise this building’s power priority.")
                    statusRow("Missing inputs", "shippingbox.and.arrow.backward.fill", AtlasTheme.finishRed, "Supply the recipe ingredients through its network or load them nearby.")
                    statusRow("Output blocked", "shippingbox.and.arrow.forward.fill", AtlasTheme.finishRed, "Withdraw goods or connect storage with free capacity.")
                    statusRow("Deposit depleted", "mountain.2.fill", AtlasTheme.finishRed, "This finite resource deposit has been exhausted.")
                }

                Section("Location and privacy") {
                    Label(
                        "Construction and manual transfers require a recent accepted location and physical proximity.",
                        systemImage: "location.fill"
                    )
                    Label(
                        "Atlasbound roads are game hexes. They do not edit or follow real street data.",
                        systemImage: "map.fill"
                    )
                    Label(
                        "Your factory is single-player and stored locally on this device.",
                        systemImage: "iphone"
                    )
                }

                Section {
                    Button {
                        dismiss()
                        onReplayTutorial()
                    } label: {
                        Label("Replay Factory tutorial", systemImage: "play.circle.fill")
                    }
                }
            }
            .navigationTitle("Factory Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func helpRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(AtlasTheme.teal, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusRow(_ name: String, _ symbol: String, _ color: Color, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}
