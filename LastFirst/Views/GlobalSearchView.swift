import SwiftUI

struct GlobalSearchView: View {
    @Binding var searchText: String

    var body: some View {
        if searchText.isEmpty {
            ContentUnavailableView("Search your library",
                systemImage: "magnifyingglass",
                description: Text("Find books, articles, and more"))
        } else {
            ContentUnavailableView("No results for \"\(searchText)\"",
                systemImage: "doc.text.magnifyingglass")
        }
    }
}
