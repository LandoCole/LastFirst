import Foundation
import SwiftData

@Model
class ReadingSessionRecord {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var wordsRead: Int
    var averageWPM: Int
    var startTokenIndex: Int
    var endTokenIndex: Int
    var readingMode: String
    var chaptersVisited: [String]
    var isSynced: Bool

    init(
        id: UUID = UUID(),
        documentId: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        durationSeconds: Int = 0,
        wordsRead: Int = 0,
        averageWPM: Int = 0,
        startTokenIndex: Int = 0,
        endTokenIndex: Int = 0,
        readingMode: String = "spritz",
        chaptersVisited: [String] = [],
        isSynced: Bool = false
    ) {
        self.id = id
        self.documentId = documentId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.wordsRead = wordsRead
        self.averageWPM = averageWPM
        self.startTokenIndex = startTokenIndex
        self.endTokenIndex = endTokenIndex
        self.readingMode = readingMode
        self.chaptersVisited = chaptersVisited
        self.isSynced = isSynced
    }
}
