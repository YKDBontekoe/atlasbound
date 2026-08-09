import Foundation
import Supabase

enum SupabaseConfiguration {
    static let projectURL = URL(string: "https://ezxelewutisuyxniozfh.supabase.co")!
    static let redirectURL = URL(string: "atlasbound://auth/callback")!

    static var publishableKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else { return nil }
        return value
    }
}

enum SupabaseClientProvider {
    static var client: SupabaseClient? {
        guard let key = SupabaseConfiguration.publishableKey else { return nil }
        return SupabaseClient(supabaseURL: SupabaseConfiguration.projectURL, supabaseKey: key)
    }
}
