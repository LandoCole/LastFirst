import Foundation

@MainActor
class DailyCurationViewModel: ObservableObject {
    @Published var curation: Curation?
    @Published var items: [CurationItem] = []
    @Published var isLoading = false

    private let userId: UUID

    init(userId: UUID) {
        self.userId = userId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let curation = try await SupabaseManager.shared.fetchTodaysCuration(userId: userId) else {
                return
            }
            self.curation = curation
            self.items = try await SupabaseManager.shared.fetchCurationItems(curationId: curation.id)
        } catch {
            print("[DailyCurationVM] Failed to load: \(error.localizedDescription)")
        }
    }

    func interact(contentId: UUID, kind: String) async {
        do {
            try await SupabaseManager.shared.postInteraction(
                userId: userId,
                contentId: contentId,
                kind: kind
            )
        } catch {
            print("[DailyCurationVM] Interaction failed: \(error.localizedDescription)")
        }
    }
}
