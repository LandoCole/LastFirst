import Foundation
import SwiftData

@Model
class ReadingStatsCache {
    @Attribute(.unique) var userId: String
    var currentStreak: Int
    var longestStreak: Int
    var totalReadingSeconds: Int
    var totalWordsRead: Int
    var lifetimeAvgWPM: Int
    var booksFinished: Int
    var daysRead: Int
    var lastSyncedAt: Date?

    init(
        userId: String,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        totalReadingSeconds: Int = 0,
        totalWordsRead: Int = 0,
        lifetimeAvgWPM: Int = 0,
        booksFinished: Int = 0,
        daysRead: Int = 0,
        lastSyncedAt: Date? = nil
    ) {
        self.userId = userId
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalReadingSeconds = totalReadingSeconds
        self.totalWordsRead = totalWordsRead
        self.lifetimeAvgWPM = lifetimeAvgWPM
        self.booksFinished = booksFinished
        self.daysRead = daysRead
        self.lastSyncedAt = lastSyncedAt
    }
}
