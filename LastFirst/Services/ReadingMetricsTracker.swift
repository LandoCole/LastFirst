import Foundation

@MainActor
class ReadingMetricsTracker: ObservableObject {
    // MARK: - Session Data
    private(set) var sessionId: UUID
    private(set) var documentId: UUID
    private(set) var sessionStart: Date
    private(set) var activeSeconds: Int = 0
    private(set) var wordsRead: Int = 0
    private(set) var startTokenIndex: Int
    private(set) var endTokenIndex: Int = 0
    private(set) var readingMode: String
    private(set) var chaptersVisited: Set<String> = []

    // MARK: - Real-time Published
    @Published var currentWPM: Int = 0

    // MARK: - Internal Tracking
    private var lastResumedAt: Date?
    private var recentWordTimestamps: [Date] = []
    private let rollingWindowSeconds: TimeInterval = 30

    // MARK: - Init

    init(documentId: UUID, startTokenIndex: Int, readingMode: ReadingMode) {
        self.sessionId = UUID()
        self.documentId = documentId
        self.sessionStart = Date()
        self.startTokenIndex = startTokenIndex
        self.endTokenIndex = startTokenIndex
        self.readingMode = readingMode.rawValue
    }

    // MARK: - Play/Pause

    func resume() {
        lastResumedAt = Date()
    }

    func pause() {
        guard let resumed = lastResumedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(resumed))
        activeSeconds += max(0, elapsed)
        lastResumedAt = nil
        updateCurrentWPM()
    }

    // MARK: - Word Advance

    func recordWordAdvance(count: Int = 1) {
        wordsRead += count
        let now = Date()
        recentWordTimestamps.append(now)
        pruneOldTimestamps(now: now)
        updateCurrentWPM()
    }

    func recordTokenIndex(_ index: Int) {
        endTokenIndex = index
    }

    // MARK: - Chapter Tracking

    func recordChapter(_ title: String) {
        chaptersVisited.insert(title)
    }

    // MARK: - Finalize

    func finalize() -> ReadingSessionRecord {
        // Accumulate any remaining active time
        if let resumed = lastResumedAt {
            let elapsed = Int(Date().timeIntervalSince(resumed))
            activeSeconds += max(0, elapsed)
            lastResumedAt = nil
        }

        let avgWPM: Int
        if activeSeconds > 0 {
            avgWPM = Int(Double(wordsRead) / (Double(activeSeconds) / 60.0))
        } else {
            avgWPM = 0
        }

        return ReadingSessionRecord(
            id: sessionId,
            documentId: documentId,
            startedAt: sessionStart,
            endedAt: Date(),
            durationSeconds: activeSeconds,
            wordsRead: wordsRead,
            averageWPM: avgWPM,
            startTokenIndex: startTokenIndex,
            endTokenIndex: endTokenIndex,
            readingMode: readingMode,
            chaptersVisited: Array(chaptersVisited),
            isSynced: false
        )
    }

    // MARK: - Private

    private func pruneOldTimestamps(now: Date) {
        let cutoff = now.addingTimeInterval(-rollingWindowSeconds)
        recentWordTimestamps.removeAll { $0 < cutoff }
    }

    private func updateCurrentWPM() {
        let now = Date()
        pruneOldTimestamps(now: now)
        guard let oldest = recentWordTimestamps.first else {
            currentWPM = 0
            return
        }
        let window = now.timeIntervalSince(oldest)
        guard window > 1 else {
            currentWPM = 0
            return
        }
        currentWPM = Int(Double(recentWordTimestamps.count) / (window / 60.0))
    }
}
