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

    let client: SupabaseClient?

    init() {
        client = SupabaseClientProvider.client
        Task { await restoreSession() }
    }

    var isConfigured: Bool { client != nil }

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
        guard let client else { return }
        do {
            session = try await client.auth.session(from: url)
            await loadProfile()
            errorMessage = nil
        }
        catch { errorMessage = error.localizedDescription }
    }

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
            session = nil
            displayName = ""
            needsProfileSetup = false
        }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteAccount() async {
        guard let client else { return }
        do {
            try await client.functions.invoke("delete-account")
            try? await client.auth.signOut()
            session = nil
            displayName = ""
            needsProfileSetup = false
        } catch { errorMessage = error.localizedDescription }
    }

    func saveDisplayName(_ value: String) async {
        guard let client, let userID = session?.user.id else { return }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(normalized.count) else {
            errorMessage = "Display name must be between 1 and 40 characters."
            return
        }
        do {
            try await client
                .from("profiles")
                .update(ProfileUpdate(displayName: normalized))
                .eq("id", value: userID.uuidString)
                .execute()
            displayName = normalized
            needsProfileSetup = false
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadProfile() async {
        guard let client, let userID = session?.user.id else { return }
        do {
            let profile: ProfileRow = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            displayName = profile.displayName
            needsProfileSetup = profile.displayName == "Explorer"
        } catch {
            needsProfileSetup = true
        }
    }
}

private struct ProfileRow: Decodable {
    let displayName: String
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

private struct ProfileUpdate: Encodable {
    let displayName: String
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}
