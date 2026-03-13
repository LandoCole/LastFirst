import Foundation
import SwiftData

struct DailyReadingPoint: Identifiable {
    let id: Date
    let date: Date
    let totalSeconds: Int
    var totalMinutes: Double { Double(totalSeconds) / 60.0 }
}

enum ChartRange: String, CaseIterable {
    case week = "7d"
    case month = "30d"

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }
}

@MainActor
class ReadingStatsViewModel: ObservableObject {
    @Published var statsCache: ReadingStatsCache?
    @Published var recentSessions: [ReadingSessionRecord] = []
    @Published var dailyReadingData: [DailyReadingPoint] = []
    @Published var todayReadingSeconds: Int = 0
    @Published var todayWPM: Int = 0
    @Published var todayWordsRead: Int = 0
    @Published var todaySessions: [ReadingSessionRecord] = []
    @Published var chartRange: ChartRange = .week {
        didSet { dailyReadingData = computeDailyData(range: chartRange) }
    }

    private let modelContext: ModelContext
    private weak var appState: AppState?
    private let userId: String
    private var allSessions: [ReadingSessionRecord] = []

    init(modelContext: ModelContext, appState: AppState?, userId: String = "local") {
        self.modelContext = modelContext
        self.appState = appState
        self.userId = userId
    }

    func load() async {
        // Fetch stats cache
        let cachePredicate = #Predicate<ReadingStatsCache> { $0.userId == userId }
        var cacheDescriptor = FetchDescriptor<ReadingStatsCache>(predicate: cachePredicate)
        cacheDescriptor.fetchLimit = 1
        statsCache = try? modelContext.fetch(cacheDescriptor).first

        // Fetch all sessions sorted by date
        let sessionDescriptor = FetchDescriptor<ReadingSessionRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        allSessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
        recentSessions = Array(allSessions.prefix(50))

        // Compute today stats
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayFiltered = allSessions.filter { $0.startedAt >= todayStart }
        todaySessions = todayFiltered
        todayReadingSeconds = todayFiltered.reduce(0) { $0 + $1.durationSeconds }

        let totalWords = todayFiltered.reduce(0) { $0 + $1.wordsRead }
        todayWordsRead = totalWords
        let totalMinutes = Double(todayReadingSeconds) / 60.0
        todayWPM = totalMinutes > 0 ? Int(Double(totalWords) / totalMinutes) : 0

        // Compute chart data
        dailyReadingData = computeDailyData(range: chartRange)
    }

    func resolveTitle(for documentId: UUID) -> String {
        appState?.library.first(where: { $0.documentId == documentId })?.title ?? "Unknown Book"
    }

    private func computeDailyData(range: ChartRange) -> [DailyReadingPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Find earliest session date
        let earliestSessionDate = allSessions.last.map { calendar.startOfDay(for: $0.startedAt) }

        // Start = earlier of (today - range.days + 1) or earliest session date
        let defaultStart = calendar.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
        let rawStart = earliestSessionDate.map { min($0, defaultStart) } ?? defaultStart

        // Group sessions by day
        var dayTotals: [Date: Int] = [:]
        for session in allSessions {
            let day = calendar.startOfDay(for: session.startedAt)
            guard day >= rawStart else { continue }
            dayTotals[day, default: 0] += session.durationSeconds
        }

        // Fill all days from rawStart to today
        let totalDays = max((calendar.dateComponents([.day], from: rawStart, to: today).day ?? 0) + 1, range.days)
        var points: [DailyReadingPoint] = []
        for offset in 0..<totalDays {
            if let day = calendar.date(byAdding: .day, value: offset, to: rawStart) {
                points.append(DailyReadingPoint(id: day, date: day, totalSeconds: dayTotals[day] ?? 0))
            }
        }
        return points
    }
}
