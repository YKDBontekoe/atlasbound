import Foundation
import Supabase

enum SupabaseConfiguration {
    static let projectURL = URL(string: "https://ezxelewutisuyxniozfh.supabase.co")!
    static let redirectURL = URL(string: "atlasbound://auth/callback")!

    static func isAuthCallback(_ url: URL) -> Bool {
        guard
            url.scheme?.caseInsensitiveCompare(redirectURL.scheme ?? "") == .orderedSame,
            url.host?.caseInsensitiveCompare(redirectURL.host ?? "") == .orderedSame,
            url.path == redirectURL.path
        else { return false }

        return true
    }

    static var publishableKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else { return nil }
        return value
    }
}

enum SupabaseClientProvider {
    static let client: SupabaseClient? = {
        guard let key = SupabaseConfiguration.publishableKey else { return nil }
        return SupabaseClient(supabaseURL: SupabaseConfiguration.projectURL, supabaseKey: key)
    }()
}
