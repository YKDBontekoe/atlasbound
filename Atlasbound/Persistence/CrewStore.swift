import Foundation
import Combine

@MainActor
final class CrewStore: ObservableObject {
    @Published private(set) var crew: CrewSummary?
    @Published private(set) var messages: [CrewChatMessage] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private let repository: CrewfrontRepository

    init(repository: CrewfrontRepository = CrewfrontRepository()) { self.repository = repository }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            crew = try await repository.loadCrew()
            if let crew {
                messages = try await repository.messages(crewID: crew.id)
            } else {
                messages = []
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func create(name: String) async {
        do { crew = try await repository.createCrew(name: name); await refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func join(code: String) async {
        do { crew = try await repository.joinCrew(code: code); await refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func send(_ message: String) async {
        guard let crew else { return }
        do { let sent = try await repository.send(message: message, crewID: crew.id); messages.insert(sent, at: 0); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func resetLocalSession() {
        crew = nil
        messages = []
        errorMessage = nil
    }
}
