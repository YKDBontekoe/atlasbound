import SwiftUI

struct CrewHubView: View {
    @ObservedObject var store: CrewStore
    @ObservedObject var auth: AuthStore
    @State private var crewName = ""
    @State private var inviteCode = ""
    @State private var draft = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AtlasTheme.Space.lg) {
                    if auth.session == nil { signedOutCard }
                    else if let crew = store.crew { activeCrew(crew) }
                    else { joinCrewCard }
                    if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(AtlasTheme.finishRed) }
                }
                .padding(AtlasTheme.Space.xl)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Crew")
            .task { await store.refresh() }
            .refreshable { await store.refresh() }
        }
    }

    private var signedOutCard: some View {
        StatSectionCard { AtlasEmptyState(title: "Sign in to form a crew", message: "Crews, chat, and live territory require an Atlasbound account.", systemImage: "person.3.fill", accent: AtlasTheme.blue) }
    }

    private var joinCrewCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(title: "Form a crew", subtitle: "Invite up to twelve explorers. Crew chat is private to members and has reporting safeguards.", systemImage: "person.3.fill", accent: AtlasTheme.blue)
                TextField("Crew name", text: $crewName).textInputAutocapitalization(.words).textFieldStyle(.roundedBorder)
                Button("Create crew") { Task { await store.create(name: crewName) } }.buttonStyle(.borderedProminent).tint(AtlasTheme.blue).disabled(crewName.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                Divider()
                TextField("Eight-character invite code", text: $inviteCode).textInputAutocapitalization(.characters).textFieldStyle(.roundedBorder)
                Button("Join crew") { Task { await store.join(code: inviteCode) } }.buttonStyle(.bordered).disabled(inviteCode.count != 8)
            }
        }
    }

    private func activeCrew(_ crew: CrewSummary) -> some View {
        VStack(spacing: AtlasTheme.Space.lg) {
            StatSectionCard {
                VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                    AtlasSectionHeader(title: crew.name, subtitle: "Seasonal territory and 2v2 Beacon sieges are preparing.", systemImage: "flag.2.crossed.fill", accent: AtlasTheme.gold)
                    AtlasMetricRow(label: "Invite code", value: crew.inviteCode, systemImage: "person.badge.key")
                    Text("Share this code only with people you trust. Live presence never shares your precise location.").font(.caption).foregroundStyle(.secondary)
                }
            }
            StatSectionCard {
                VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                    AtlasSectionHeader(title: "Crew chat", subtitle: "No direct messages or links. Report harmful content from the upcoming message menu.", systemImage: "bubble.left.and.bubble.right.fill", accent: AtlasTheme.teal)
                    ForEach(store.messages) { message in
                        VStack(alignment: .leading, spacing: 2) { Text(message.body).font(.subheadline); Text(message.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                        Divider()
                    }
                    HStack { TextField("Message crew", text: $draft).textFieldStyle(.roundedBorder); Button("Send") { let text = draft; draft = ""; Task { await store.send(text) } }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }
        }
    }
}
