import Foundation

@MainActor
class CatalogViewModel: ObservableObject {
    @Published var items: [CatalogItem] = []
    @Published var isLoading = false

    func load() async {
        guard items.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await SupabaseManager.shared.fetchCatalogItems()
        } catch {
            print("[CatalogViewModel] Failed to load catalog: \(error.localizedDescription)")
        }
    }
}
