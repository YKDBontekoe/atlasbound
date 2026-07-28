import SwiftUI

struct ActivityTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore

    @State private var selectedSession: PersistedActivityRecord?

    private var recentSessions: [PersistedActivityRecord] {
        Array(activityHistory.sessions.suffix(3).reversed())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: controller.recorder.activityType.symbolName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AtlasTheme.blue)
                            .frame(width: 44, height: 44)
                            .background(AtlasTheme.blue.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(controller.isRecording ? controller.recorder.activityType.activeTitle : "Ready to explore")
                                .font(.headline)
                            Text(controller.isRecording
                                  ? "Recording \(controller.recorder.activityType.displayName.lowercased()) tiles"
                                  : controller.recorder.activityType.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(ActivityType.selectableCases, id: \.self) { type in
                        Button {
                            controller.setActivityType(type)
                            AtlasHaptics.select()
                        } label: {
                            ActivityTypeRow(
                                type: type,
                                isSelected: controller.recorder.activityType == type
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isRecording)
                    }
                } header: {
                    Text("Activity type")
                } footer: {
                    Text(controller.isRecording
                          ? "Finish the current session before switching activities."
                          : "Each activity uses its own reveal grid width.")
                }

                Section {
                    if recentSessions.isEmpty {
                        ContentUnavailableView {
                            Label("No sessions yet", systemImage: "clock.arrow.circlepath")
                        } description: {
                            Text("Your finished activities will appear here.")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(recentSessions) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                ActivityHistoryRow(session: session)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .transition(.opacity)
                        }

                        NavigationLink {
                            ActivityHistoryView(activityHistory: activityHistory)
                        } label: {
                            Text("See all activities")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("seeAllActivities")
                    }
                } header: {
                    Text("Recent activities")
                }

                Section("This atlas") {
                    HStack(spacing: 0) {
                        StatKPI(value: "\(store.activitiesCompleted)", caption: "Activities")
                        StatKPI(value: "\(store.discoveredTiles.count)", caption: "Tiles", accent: AtlasTheme.teal)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    if let summary = controller.lastSummary {
                        LabeledContent("Last session", value: "+\(summary.tilesDiscovered) new · \(StatsFormat.distance(summary.distanceMeters))")
                    }
                }
            }
            .navigationTitle("Activity")
            .sheet(item: $selectedSession) { session in
                ActivitySessionDetailView(session: session) {
                    selectedSession = nil
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}
