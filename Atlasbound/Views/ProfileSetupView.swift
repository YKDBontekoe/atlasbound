import SwiftUI

struct ProfileSetupView: View {
    @ObservedObject var auth: AuthStore
    @State private var displayName = ""
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose the name shown for your Atlasbound account.")
                        .foregroundStyle(.secondary)
                    TextField("Display name", text: $displayName)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                Section {
                    Button {
                        Task {
                            isSaving = true
                            await auth.saveDisplayName(displayName)
                            isSaving = false
                        }
                    } label: {
                        HStack {
                            Text("Continue")
                            Spacer()
                            if isSaving { ProgressView() }
                        }
                    }
                    .disabled(isSaving)
                }
                if let errorMessage = auth.errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("Delete account and all progress", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Your explorer profile")
            .onAppear { displayName = auth.displayName == "Explorer" ? "" : auth.displayName }
            .confirmationDialog(
                "Delete your Atlasbound account?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete permanently", role: .destructive) {
                    Task { await auth.deleteAccount() }
                }
            } message: {
                Text("This removes your cloud profile and all game progress.")
            }
        }
    }
}
