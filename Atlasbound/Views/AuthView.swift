import SwiftUI

struct AuthView: View {
    @ObservedObject var auth: AuthStore
    @State private var email = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sign in to keep your atlas, territory, and explorer progress synced across devices.")
                        .foregroundStyle(.secondary)
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }
                Section {
                    Button {
                        Task {
                            isSending = true
                            await auth.sendMagicLink(email: email)
                            isSending = false
                        }
                    } label: {
                        HStack {
                            Text("Send magic link")
                            Spacer()
                            if isSending { ProgressView() }
                        }
                    }
                    .disabled(isSending)
                }
                if auth.magicLinkSent {
                    Section { Label("Check your inbox for the sign-in link.", systemImage: "envelope.badge").foregroundStyle(.green) }
                }
                if let errorMessage = auth.errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Atlasbound")
        }
    }
}
