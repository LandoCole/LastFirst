import Foundation

struct CurationFilter: Equatable {
    var genre: String?
    var maxLengthMinutes: Int?
    var author: String?
    var searchQuery: String?

    var isActive: Bool {
        genre != nil || maxLengthMinutes != nil || author != nil || (searchQuery ?? "").count > 0
    }

    func matches(_ item: CurationItem) -> Bool {
        if let genre, let topics = item.content?.topics {
            guard topics.contains(where: { $0.localizedCaseInsensitiveContains(genre) }) else { return false }
        }
        if let maxLengthMinutes, let readMinutes = item.content?.estimatedReadMinutes {
            guard readMinutes <= maxLengthMinutes else { return false }
        }
        if let author, !author.isEmpty {
            let itemAuthor = item.displayAuthor ?? ""
            guard itemAuthor.localizedCaseInsensitiveContains(author) else { return false }
        }
        if let searchQuery, !searchQuery.isEmpty {
            let title = item.displayTitle.lowercased()
            let summary = item.displaySummary?.lowercased() ?? ""
            let query = searchQuery.lowercased()
            guard title.contains(query) || summary.contains(query) else { return false }
        }
        return true
    }

    mutating func clearAll() {
        genre = nil
        maxLengthMinutes = nil
        author = nil
        searchQuery = nil
    }
}
