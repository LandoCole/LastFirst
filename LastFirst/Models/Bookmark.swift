import Foundation

struct Bookmark: Identifiable, Codable {
    let id: UUID
    var bookId: UUID
    var title: String?
    var text: String
    var startWordIndex: Int
    var endWordIndex: Int
    var dateCreated: Date
    var note: String?

    init(
        id: UUID = UUID(),
        bookId: UUID,
        title: String? = nil,
        text: String,
        startWordIndex: Int,
        endWordIndex: Int,
        dateCreated: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.bookId = bookId
        self.title = title
        self.text = text
        self.startWordIndex = startWordIndex
        self.endWordIndex = endWordIndex
        self.dateCreated = dateCreated
        self.note = note
    }
}

struct SavedImage: Identifiable, Codable {
    let id: UUID
    var bookId: UUID
    var imageData: Data
    var pageIndex: Int
    var wordIndex: Int
    var isSeen: Bool
    var isBookmarked: Bool
    var dateFound: Date

    init(
        id: UUID = UUID(),
        bookId: UUID,
        imageData: Data,
        pageIndex: Int,
        wordIndex: Int,
        isSeen: Bool = false,
        isBookmarked: Bool = false,
        dateFound: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.imageData = imageData
        self.pageIndex = pageIndex
        self.wordIndex = wordIndex
        self.isSeen = isSeen
        self.isBookmarked = isBookmarked
        self.dateFound = dateFound
    }
}

struct SavedImageMetadata: Identifiable, Codable {
    let id: UUID
    var bookId: UUID
    var pageIndex: Int
    var wordIndex: Int
    var isSeen: Bool
    var isBookmarked: Bool
    var dateFound: Date

    init(
        id: UUID = UUID(),
        bookId: UUID,
        pageIndex: Int,
        wordIndex: Int,
        isSeen: Bool = false,
        isBookmarked: Bool = false,
        dateFound: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.pageIndex = pageIndex
        self.wordIndex = wordIndex
        self.isSeen = isSeen
        self.isBookmarked = isBookmarked
        self.dateFound = dateFound
    }
}

struct Footnote: Identifiable, Codable {
    let id: UUID
    var bookId: UUID
    var indicator: String
    var content: String
    var wordIndex: Int
    var contextText: String?
    var dateFound: Date

    init(
        id: UUID = UUID(),
        bookId: UUID,
        indicator: String,
        content: String,
        wordIndex: Int,
        contextText: String? = nil,
        dateFound: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.indicator = indicator
        self.content = content
        self.wordIndex = wordIndex
        self.contextText = contextText
        self.dateFound = dateFound
    }
}
