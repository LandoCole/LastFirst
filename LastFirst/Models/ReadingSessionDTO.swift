import Foundation

struct ReadingSessionDTO: Codable {
    var id: UUID
    var userId: UUID
    var documentId: UUID
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var wordsRead: Int
    var averageWpm: Int?
    var startTokenIndex: Int?
    var endTokenIndex: Int?
    var readingMode: String?
    var chaptersVisited: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case documentId = "document_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case wordsRead = "words_read"
        case averageWpm = "average_wpm"
        case startTokenIndex = "start_token_index"
        case endTokenIndex = "end_token_index"
        case readingMode = "reading_mode"
        case chaptersVisited = "chapters_visited"
    }

    init(from record: ReadingSessionRecord, userId: UUID) {
        self.id = record.id
        self.userId = userId
        self.documentId = record.documentId
        self.startedAt = record.startedAt
        self.endedAt = record.endedAt
        self.durationSeconds = record.durationSeconds
        self.wordsRead = record.wordsRead
        self.averageWpm = record.averageWPM
        self.startTokenIndex = record.startTokenIndex
        self.endTokenIndex = record.endTokenIndex
        self.readingMode = record.readingMode
        self.chaptersVisited = record.chaptersVisited
    }
}

struct UserReadingStatsDTO: Codable {
    var totalReadingSeconds: Int
    var totalWordsRead: Int
    var lifetimeAvgWpm: Int?
    var booksTouched: Int
    var daysRead: Int

    enum CodingKeys: String, CodingKey {
        case totalReadingSeconds = "total_reading_seconds"
        case totalWordsRead = "total_words_read"
        case lifetimeAvgWpm = "lifetime_avg_wpm"
        case booksTouched = "books_touched"
        case daysRead = "days_read"
    }
}

struct ReadingStreakDTO: Codable {
    var currentStreak: Int
    var longestStreak: Int

    enum CodingKeys: String, CodingKey {
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
    }
}
