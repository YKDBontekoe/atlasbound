import SwiftUI

struct LiveMapOptionsSheet: View {
    @Binding var selectedStyleRaw: String
    @Binding var selectedDataLayerRaw: String
    @Binding var uses3DMap: Bool
    @Binding var showsMastery: Bool
    @Binding var showsPlaces: Bool
    @Binding var showsFog: Bool
    @Binding var showsFrontier: Bool
    @Binding var showsFactory: Bool
    let explorerLevel: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Map style") {
                    ForEach(LiveMapStyle.allCases) { style in
                        let unlocked = explorerLevel >= style.requiredLevel
                        Button {
                            guard unlocked else { return }
                            selectedStyleRaw = style.rawValue
                            AtlasHaptics.select()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: style.symbolName)
                                    .foregroundStyle(unlocked ? AtlasTheme.blue : .secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(style.displayName)
                                        .foregroundStyle(.primary)
                                    Text(unlocked ? style.detail : "Unlocks at explorer level \(style.requiredLevel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedStyleRaw == style.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AtlasTheme.blue)
                                } else if !unlocked {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!unlocked)
                    }

                    Toggle(isOn: $uses3DMap) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("3D terrain")
                                Text(
                                    explorerLevel >= ExplorerProgressionEngine.threeDMapRequiredLevel
                                        ? "Pitch the camera with realistic elevation"
                                        : "Unlocks at explorer level \(ExplorerProgressionEngine.threeDMapRequiredLevel)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "cube.fill")
                                .foregroundStyle(
                                    explorerLevel >= ExplorerProgressionEngine.threeDMapRequiredLevel
                                        ? AtlasTheme.blue
                                        : Color.secondary
                                )
                        }
                    }
                    .disabled(explorerLevel < ExplorerProgressionEngine.threeDMapRequiredLevel)
                    .tint(AtlasTheme.blue)
                }

                Section("Atlas layers") {
                    ForEach(LiveMapDataLayer.allCases) { layer in
                        let unlocked = explorerLevel >= layer.requiredLevel
                        Button {
                            guard unlocked else { return }
                            selectedDataLayerRaw = layer.rawValue
                            AtlasHaptics.select()
                        } label: {
                            HStack {
                                Label(layer.displayName, systemImage: layer.symbolName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedDataLayerRaw == layer.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AtlasTheme.blue)
                                } else if !unlocked {
                                    Text("Level \(layer.requiredLevel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!unlocked)
                    }

                    layerToggle(
                        "Mastery markers",
                        detail: "Show high-rank tile badges",
                        symbol: "star.hexagon.fill",
                        isOn: $showsMastery
                    )
                    layerToggle(
                        "Places visited",
                        detail: "Label resolved cities and localities",
                        symbol: "mappin.circle.fill",
                        isOn: $showsPlaces
                    )
                    layerToggle(
                        "Nearby fog",
                        detail: "Reveal the hex grid around you",
                        symbol: "cloud.fog.fill",
                        isOn: $showsFog
                    )
                    layerToggle(
                        "Frontier",
                        detail: "Show expedition edges and target sectors",
                        symbol: "flag.2.crossed.fill",
                        isOn: $showsFrontier
                    )
                    layerToggle(
                        "Factory",
                        detail: "Show roads, buildings, and production alerts",
                        symbol: "gearshape.2.fill",
                        isOn: $showsFactory
                    )
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Map legend")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            legendDot(color: AtlasTheme.teal, text: "Discovered")
                            legendDot(color: AtlasTheme.surveyedBlue, text: "Surveyed")
                            legendDot(color: AtlasTheme.gold, text: "Mastered")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Map & Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func layerToggle(
        _ title: String,
        detail: String,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(AtlasTheme.blue)
            }
        }
        .tint(AtlasTheme.blue)
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2)
        }
    }
}
