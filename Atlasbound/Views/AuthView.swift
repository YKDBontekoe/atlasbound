import SwiftUI

struct AuthView: View {
    @ObservedObject var auth: AuthStore
    @State private var email = ""
    @State private var isSending = false
    @FocusState private var emailFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Keep your atlas with you", systemImage: "icloud.and.arrow.up")
                        .font(.headline)
                    Text("Use a secure magic link to sync progress across devices and join shared treasure adventures. No password to remember.")
                        .foregroundStyle(.secondary)
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .focused($emailFocused)
                }
                Section {
                    Button {
                        Task {
                            isSending = true
                            emailFocused = false
                            await auth.sendMagicLink(email: email)
                            isSending = false
                        }
                    } label: {
                        HStack {
                            Text(auth.magicLinkSent ? "Send again" : "Email me a sign-in link")
                            Spacer()
                            if isSending { ProgressView() }
                        }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                if auth.magicLinkSent {
                    Section {
                        Label("Check your inbox", systemImage: "envelope.badge")
                            .foregroundStyle(.green)
                        Text("We sent a sign-in link to (email.trimmingCharacters(in: .whitespacesAndNewlines)). Return here after tapping it. You can resend if it does not arrive.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage = auth.errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: email) { _, _ in
                auth.clearMagicLinkSent()
            }
            .onChange(of: auth.session?.user.id) { _, newValue in
                if newValue != nil { dismiss() }
            }
        }
    }
}
