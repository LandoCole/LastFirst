import Foundation

// MARK: - Cover Content Type

enum CoverContentType {
    case epub      // has proper cover art — no title overlay
    case pdf       // show title + image
    case article   // show title + image
    case unknown   // treat like article
}

// MARK: - Ribbon & Preview Enums

enum RibbonState: Equatable {
    case none           // not in library (CatalogItem)
    case added          // in library, not downloaded
    case downloaded     // downloaded
}

enum PreviewButtonMode {
    case addToLibrary               // CatalogItem not yet added
    case open                       // LibraryItem, never read
    case resume                     // LibraryItem, in progress or completed
}

// MARK: - PreviewableItem Protocol

protocol PreviewableItem: Identifiable {
    var id: UUID { get }
    var title: String { get }
    var author: String? { get }
    var previewDocumentId: UUID? { get }
    var ribbonState: RibbonState { get }
    var previewButtonMode: PreviewButtonMode { get }
}

// MARK: - DownloadState

enum DownloadState: Codable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded

    private enum CodingKeys: String, CodingKey {
        case type
        case progress
    }

    private enum StateType: String, Codable {
        case notDownloaded
        case downloading
        case downloaded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StateType.self, forKey: .type)
        switch type {
        case .notDownloaded:
            self = .notDownloaded
        case .downloading:
            let progress = try container.decode(Double.self, forKey: .progress)
            self = .downloading(progress: progress)
        case .downloaded:
            self = .downloaded
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notDownloaded:
            try container.encode(StateType.notDownloaded, forKey: .type)
        case .downloading(let progress):
            try container.encode(StateType.downloading, forKey: .type)
            try container.encode(progress, forKey: .progress)
        case .downloaded:
            try container.encode(StateType.downloaded, forKey: .type)
        }
    }
}

// MARK: - LibraryItem

struct LibraryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var documentId: UUID
    var source: LibrarySource

    var title: String
    var author: String?

    var dateAdded: Date
    var lastOpenedAt: Date?

    var progress: ReadingProgress

    var lastChapterTitle: String?
    var wordCount: Int?
    var downloadState: DownloadState

    enum InferredReadingStatus: Hashable {
        case reading, completed, wantToRead
    }

    var inferredStatus: InferredReadingStatus {
        if progress.percentComplete >= 100 { return .completed }
        if progress.percentComplete > 0 || lastOpenedAt != nil { return .reading }
        return .wantToRead
    }

    init(
        id: UUID = UUID(),
        documentId: UUID,
        source: LibrarySource,
        title: String,
        author: String? = nil,
        dateAdded: Date = Date(),
        lastOpenedAt: Date? = nil,
        progress: ReadingProgress = ReadingProgress(),
        lastChapterTitle: String? = nil,
        wordCount: Int? = nil,
        downloadState: DownloadState = .downloaded
    ) {
        self.id = id
        self.documentId = documentId
        self.source = source
        self.title = title
        self.author = author
        self.dateAdded = dateAdded
        self.lastOpenedAt = lastOpenedAt
        self.progress = progress
        self.lastChapterTitle = lastChapterTitle
        self.wordCount = wordCount
        self.downloadState = downloadState
    }

    // Custom decoder to handle missing downloadState for backward compat
    private enum CodingKeys: String, CodingKey {
        case id, documentId, source, title, author, dateAdded, lastOpenedAt
        case progress, lastChapterTitle, wordCount, downloadState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        documentId = try container.decode(UUID.self, forKey: .documentId)
        source = try container.decode(LibrarySource.self, forKey: .source)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        progress = try container.decode(ReadingProgress.self, forKey: .progress)
        lastChapterTitle = try container.decodeIfPresent(String.self, forKey: .lastChapterTitle)
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount)
        downloadState = try container.decodeIfPresent(DownloadState.self, forKey: .downloadState) ?? .downloaded
    }
}

// MARK: - LibraryItem Helpers

extension LibraryItem {
    var coverIconName: String {
        switch source {
        case .localFile(let local):
            switch local.fileType {
            case .epub: return "book.closed.fill"
            case .pdf: return "doc.fill"
            }
        case .web:
            return "globe"
        case .curated(let c):
            switch c.fileType {
            case "epub": return "book.closed.fill"
            case "pdf": return "doc.fill"
            default: return "newspaper.fill"
            }
        }
    }

    var curatedCoverURL: URL? {
        if case .curated(let c) = source { return c.coverUrl }
        return nil
    }

    var coverContentType: CoverContentType {
        switch source {
        case .localFile(let f): return f.fileType == .epub ? .epub : .pdf
        case .web: return .article
        case .curated(let c):
            switch c.fileType {
            case "epub": return .epub
            case "pdf": return .pdf
            default: return .article
            }
        }
    }
}

// MARK: - LibraryItem + PreviewableItem

extension LibraryItem: PreviewableItem {
    var previewDocumentId: UUID? { documentId }

    var ribbonState: RibbonState {
        switch downloadState {
        case .notDownloaded, .downloading:
            return .added
        case .downloaded:
            return .downloaded
        }
    }

    var previewButtonMode: PreviewButtonMode {
        switch inferredStatus {
        case .wantToRead:
            return .open
        case .reading, .completed:
            return .resume
        }
    }
}

enum LibrarySource: Codable, Equatable {
    case localFile(LocalFile)
    case web(Web)
    case curated(Curated)

    struct LocalFile: Codable, Equatable {
        var fileURL: URL
        var fileType: DocumentSource.LocalFileType

        init(fileURL: URL, fileType: DocumentSource.LocalFileType) {
            self.fileURL = fileURL
            self.fileType = fileType
        }
    }

    struct Web: Codable, Equatable {
        var url: URL
        var lastRefreshedAt: Date?

        init(url: URL, lastRefreshedAt: Date? = nil) {
            self.url = url
            self.lastRefreshedAt = lastRefreshedAt
        }
    }

    struct Curated: Codable, Equatable {
        var contentId: UUID
        var sourceUrl: URL?
        var coverUrl: URL?
        var fileType: String?    // "epub", "pdf", "web", "article"
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case localFile
        case web
        case curated
    }

    private enum SourceType: String, Codable {
        case localFile
        case web
        case curated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SourceType.self, forKey: .type)
        switch type {
        case .localFile:
            self = .localFile(try container.decode(LocalFile.self, forKey: .localFile))
        case .web:
            self = .web(try container.decode(Web.self, forKey: .web))
        case .curated:
            self = .curated(try container.decode(Curated.self, forKey: .curated))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .localFile(let value):
            try container.encode(SourceType.localFile, forKey: .type)
            try container.encode(value, forKey: .localFile)
        case .web(let value):
            try container.encode(SourceType.web, forKey: .type)
            try container.encode(value, forKey: .web)
        case .curated(let value):
            try container.encode(SourceType.curated, forKey: .type)
            try container.encode(value, forKey: .curated)
        }
    }
}
