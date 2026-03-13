import Foundation

/// Unified content model that replaces CatalogItem.
/// Maps to the `content` table in Supabase.
struct ContentItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var sourceType: String        // 'rss', 'arxiv', 'openlibrary', 'web', 'manual'
    var sourceUrl: String?
    var title: String
    var author: String?
    var summary: String?
    var topics: [String]?
    var difficultyLevel: String?
    var wordCount: Int?
    var estimatedReadMinutes: Int?
    var coverUrl: String?
    var downloadUrl: String?
    var fileType: String?         // 'epub', 'pdf', 'web'
    var isAvailable: Bool?
    var popularityScore: Double?
    var qualityScore: Double?
    var freshnessScore: Double?
    var isbn: String?
    var openLibraryKey: String?
    var availability: String?       // 'full_text', 'downloadable', 'external_purchase', 'paywalled'
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, author, summary, topics, isbn, availability
        case sourceType = "source_type"
        case sourceUrl = "source_url"
        case difficultyLevel = "difficulty_level"
        case wordCount = "word_count"
        case estimatedReadMinutes = "estimated_read_minutes"
        case coverUrl = "cover_url"
        case downloadUrl = "download_url"
        case fileType = "file_type"
        case isAvailable = "is_available"
        case popularityScore = "popularity_score"
        case qualityScore = "quality_score"
        case freshnessScore = "freshness_score"
        case openLibraryKey = "open_library_key"
        case createdAt = "created_at"
    }

    var coverURL: URL? {
        guard let coverUrl else { return nil }
        return URL(string: coverUrl)
    }

    var downloadURL: URL? {
        guard let downloadUrl else { return nil }
        return URL(string: downloadUrl)
    }

    /// Convert to a CatalogItem for backward compatibility with existing views.
    var asCatalogItem: CatalogItem {
        CatalogItem(
            id: id,
            title: title,
            author: author,
            coverURL: coverURL,
            downloadURL: downloadURL,
            fileType: fileType,
            wordCount: wordCount,
            description: summary
        )
    }
}
