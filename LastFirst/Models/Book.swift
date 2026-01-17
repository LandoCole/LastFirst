import Foundation

struct Book: Identifiable, Codable {
    let id: UUID
    var title: String
    var author: String
    var coverImageData: Data?
    var filePath: String
    var fileType: FileType
    var chapters: [Chapter]
    var lastReadPosition: ReadingPosition
    var dateAdded: Date
    var lastOpened: Date?
    var totalWords: Int

    enum FileType: String, Codable {
        case epub
        case pdf
        case txt
    }

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "Unknown Author",
        coverImageData: Data? = nil,
        filePath: String,
        fileType: FileType,
        chapters: [Chapter] = [],
        lastReadPosition: ReadingPosition = ReadingPosition(),
        dateAdded: Date = Date(),
        lastOpened: Date? = nil,
        totalWords: Int = 0
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageData = coverImageData
        self.filePath = filePath
        self.fileType = fileType
        self.chapters = chapters
        self.lastReadPosition = lastReadPosition
        self.dateAdded = dateAdded
        self.lastOpened = lastOpened
        self.totalWords = totalWords
    }

    var validURL: URL {
        let url = URL(fileURLWithPath: filePath)
        if FileManager.default.fileExists(atPath: filePath) {
            return url
        }
        // Fallback: Try to find the file in the Documents directory
        let filename = url.lastPathComponent
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fallbackURL = documents.appendingPathComponent(filename)
        return fallbackURL
    }
}

struct Chapter: Identifiable, Codable {
    let id: UUID
    var title: String
    var startWordIndex: Int
    var endWordIndex: Int

    init(id: UUID = UUID(), title: String, startWordIndex: Int, endWordIndex: Int) {
        self.id = id
        self.title = title
        self.startWordIndex = startWordIndex
        self.endWordIndex = endWordIndex
    }
}

struct ReadingPosition: Codable {
    var wordIndex: Int
    var chapterIndex: Int
    var percentComplete: Double

    init(wordIndex: Int = 0, chapterIndex: Int = 0, percentComplete: Double = 0.0) {
        self.wordIndex = wordIndex
        self.chapterIndex = chapterIndex
        self.percentComplete = percentComplete
    }
}
