import Foundation
import Supabase

struct CrewSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let inviteCode: String
    enum CodingKeys: String, CodingKey { case id, name; case inviteCode = "invite_code" }
}

struct CrewChatMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let authorID: UUID
    let body: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, body; case authorID = "author_id"; case createdAt = "created_at" }
}

final class CrewfrontRepository {
    private let client: SupabaseClient?
    init(client: SupabaseClient? = SupabaseClientProvider.authenticatedClient) { self.client = client }

    func loadCrew() async throws -> CrewSummary? {
        guard let client else { return nil }
        struct Membership: Decodable { let crewID: UUID; enum CodingKeys: String, CodingKey { case crewID = "crew_id" } }
        let memberships: [Membership] = try await client.from("crew_members").select("crew_id").limit(1).execute().value
        guard let membership = memberships.first else { return nil }
        return try await client.from("crews").select("id,name,invite_code").eq("id", value: membership.crewID.uuidString).maybeSingle().execute().value
    }

    func messages(crewID: UUID) async throws -> [CrewChatMessage] {
        guard let client else { return [] }
        return try await client.from("crew_chat_messages").select("id,author_id,body,created_at").eq("crew_id", value: crewID.uuidString).order("created_at", ascending: false).limit(50).execute().value
    }

    func createCrew(name: String) async throws -> CrewSummary {
        try await invoke(action: "create_crew", name: name)
    }

    func joinCrew(code: String) async throws -> CrewSummary {
        try await invoke(action: "join_crew", inviteCode: code)
    }

    func send(message: String, crewID: UUID) async throws -> CrewChatMessage {
        guard let client else { throw CrewfrontError.notConfigured }
        struct Request: Encodable { let action = "send_chat"; let crewID: String; let message: String; enum CodingKeys: String, CodingKey { case action; case crewID = "crew_id"; case message } }
        return try await client.functions.invoke("crewfront", options: FunctionInvokeOptions(body: Request(crewID: crewID.uuidString, message: message)))
    }

    private func invoke(action: String, name: String? = nil, inviteCode: String? = nil) async throws -> CrewSummary {
        guard let client else { throw CrewfrontError.notConfigured }
        struct Request: Encodable { let action: String; let name: String?; let inviteCode: String?; enum CodingKeys: String, CodingKey { case action, name; case inviteCode = "invite_code" } }
        return try await client.functions.invoke("crewfront", options: FunctionInvokeOptions(body: Request(action: action, name: name, inviteCode: inviteCode)))
    }
}

enum CrewfrontError: LocalizedError { case notConfigured
    var errorDescription: String? { "Crewfront needs a signed-in Atlasbound account." }
}
