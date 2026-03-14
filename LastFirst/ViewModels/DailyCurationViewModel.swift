import Foundation

@MainActor
class DailyCurationViewModel: ObservableObject {
    @Published var curation: Curation?
    @Published var items: [CurationItem] = []
    @Published var isLoading = false
    @Published var isGenerating = false

    private let userId: UUID

    init(userId: UUID) {
        self.userId = userId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Try ready curation first
            if let curation = try await SupabaseManager.shared.fetchTodaysCuration(userId: userId) {
                self.curation = curation
                self.items = try await SupabaseManager.shared.fetchCurationItems(curationId: curation.id)
                self.isGenerating = false
                return
            }

            // Check if there's a curation still being generated (researching status)
            if let pendingCuration = try await SupabaseManager.shared.fetchTodaysPendingCuration(userId: userId) {
                self.isGenerating = true
                self.curation = pendingCuration
                // Poll until ready
                await pollUntilReady(curationId: pendingCuration.id)
            }
        } catch {
            print("[DailyCurationVM] Failed to load: \(error.localizedDescription)")
        }
    }

    private func pollUntilReady(curationId: UUID) async {
        while !Task.isCancelled {
            if let curation = try? await SupabaseManager.shared.fetchCuration(id: curationId) {
                if curation.status == "ready" {
                    self.curation = curation
                    self.items = (try? await SupabaseManager.shared.fetchCurationItems(curationId: curationId)) ?? []
                    self.isGenerating = false
                    return
                }
                if curation.status == "error" {
                    self.isGenerating = false
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s polling for daily
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
