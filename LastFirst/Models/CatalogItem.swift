import Foundation

struct CatalogItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var author: String?
    var coverURL: URL?
    var downloadURL: URL?
    var fileType: String?     // "epub", "pdf"
    var wordCount: Int?
    var description: String?

    enum CodingKeys: String, CodingKey {
        case id, title, author, description
        case coverURL = "cover_url"
        case downloadURL = "download_url"
        case fileType = "file_type"
        case wordCount = "word_count"
    }
}

// MARK: - CatalogItem + PreviewableItem

extension CatalogItem: PreviewableItem {
    var previewDocumentId: UUID? { nil }

    var ribbonState: RibbonState { .none }

    var previewButtonMode: PreviewButtonMode { .addToLibrary }
}
