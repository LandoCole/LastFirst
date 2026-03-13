import Foundation

@MainActor
class CurationCreationViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var searchText: String = ""
    @Published var selectedItemIds: Set<UUID> = []
    var editingListId: UUID?

    func filteredItems(from library: [LibraryItem]) -> [LibraryItem] {
        guard !searchText.isEmpty else { return library }
        let query = searchText.lowercased()
        return library.filter { item in
            item.title.lowercased().contains(query) ||
            (item.author ?? "").lowercased().contains(query)
        }
    }

    func localSuggest(from library: [LibraryItem]) {
        let keywords = name
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }

        guard !keywords.isEmpty else { return }

        for item in library {
            let haystack = (item.title + " " + (item.author ?? "")).lowercased()
            let score = keywords.reduce(0) { total, keyword in
                total + (haystack.contains(keyword) ? 1 : 0)
            }
            if score > 0 {
                selectedItemIds.insert(item.id)
            }
        }
    }

    func loadExisting(list: ReadingList, library: [LibraryItem]) {
        editingListId = list.id
        name = list.name
        selectedItemIds = Set(list.itemIds)
    }

    func selectAll(from library: [LibraryItem]) {
        let visible = filteredItems(from: library)
        for item in visible {
            selectedItemIds.insert(item.id)
        }
    }

    func deselectAll() {
        selectedItemIds.removeAll()
    }
}
