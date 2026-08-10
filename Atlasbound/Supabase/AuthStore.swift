import Combine
import Foundation
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var magicLinkSent = false
    @Published private(set) var displayName = ""
    @Published private(set) var needsProfileSetup = false
    var onSessionEnded: (@MainActor () -> Void)?
    /// Set by the guest sign-in flow when cancelling should return to the
    /// existing local atlas instead of clearing it.
    var preserveLocalStateOnSignOut = false

    let client: SupabaseClient?
    private let dataClient: SupabaseClient?

    init() {
        client = SupabaseClientProvider.client
        dataClient = SupabaseClientProvider.authenticatedClient
        Task { await restoreSession() }
    }

    var isConfigured: Bool { client != nil }

    func clearMagicLinkSent() {
        magicLinkSent = false
    }

    func restoreSession() async {
        guard let client else {
            isLoading = false
            errorMessage = "Supabase is not configured. Add SUPABASE_PUBLISHABLE_KEY to the app configuration."
            return
        }
        do {
            session = try await client.auth.session
            await loadProfile()
        } catch { session = nil }
        isLoading = false
    }

    func sendMagicLink(email: String) async {
        guard let client else { errorMessage = "Supabase is not configured."; return }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else {
            errorMessage = "Enter a valid email address."
            return
        }
        do {
            try await client.auth.signInWithOTP(email: normalized, redirectTo: SupabaseConfiguration.redirectURL)
            errorMessage = nil
            magicLinkSent = true
        } catch { errorMessage = error.localizedDescription }
    }

    func handle(url: URL) async {
        guard SupabaseConfiguration.isAuthCallback(url) else { return }
        guard let client else { return }
        do {
            session = try await client.auth.session(from: url)
            if await loadProfile() {
                errorMessage = nil
            }
        }
        catch { errorMessage = error.localizedDescription }
    }

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
            resetSessionState()
        }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteAccount() async {
        guard let dataClient, let authClient = client else { return }
        do {
            try await dataClient.functions.invoke("delete-account")
            try? await authClient.auth.signOut()
            resetSessionState()
        } catch { errorMessage = error.localizedDescription }
    }

    func saveDisplayName(_ value: String) async {
        guard let dataClient, let userID = session?.user.id else { return }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(normalized.count) else {
            errorMessage = "Display name must be between 1 and 40 characters."
            return
        }
        do {
            try await dataClient
                .from("profiles")
                .update(ProfileUpdate(displayName: normalized, profileCompleted: true))
                .eq("id", value: userID.uuidString)
                .execute()
            displayName = normalized
            needsProfileSetup = false
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    private func loadProfile() async -> Bool {
        guard let dataClient, let userID = session?.user.id else { return false }
        do {
            let profile: ProfileRow? = try await dataClient
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .maybeSingle()
                .execute()
                .value
            guard let profile else {
                displayName = ""
                needsProfileSetup = true
                return true
            }
            displayName = profile.displayName
            needsProfileSetup = !profile.profileCompleted
            return true
        } catch {
            errorMessage = "Couldn’t load your profile. Check your connection and try again."
            return false
        }
    }

    private func resetSessionState() {
        session = nil
        displayName = ""
        needsProfileSetup = false
        magicLinkSent = false
        onSessionEnded?()
    }
}

private struct ProfileRow: Decodable {
    let displayName: String
    let profileCompleted: Bool
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case profileCompleted = "profile_completed"
    }
}

private struct ProfileUpdate: Encodable {
    let displayName: String
    let profileCompleted: Bool
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case profileCompleted = "profile_completed"
    }
}
