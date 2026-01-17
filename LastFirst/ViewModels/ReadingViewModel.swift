import Foundation
import SwiftUI
import Combine

class ReadingViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isPlaying: Bool = false
    @Published var currentWordIndex: Int = 0
    @Published var wordsPerMinute: Int = 300
    @Published var readingMode: ReadingMode = .spritz
    @Published var isDialPushedDown: Bool = false
    
    var isPaused: Bool { !isPlaying }
    
    // MARK: - Loading State
    @Published var isLoading: Bool = false
    @Published var loadingError: Error?

    // MARK: - Stream Mode (no longer needs state - uses line-based rendering)

    // MARK: - Bookmark Creation
    @Published var isCreatingBookmark: Bool = false
    @Published var bookmarkStartIndex: Int = 0
    @Published var bookmarkEndIndex: Int = 0

    // MARK: - Content
    @Published private(set) var words: [String] = []
    @Published private(set) var chapters: [Chapter] = []
    @Published private var currentChapterIndex: Int = 0

    // MARK: - Soft Start
    private var softStartPercentage: Double = 0.6
    private var currentSoftStartWPM: Int = 0
    private var softStartStartTime: Date?
    private let softStartDuration: TimeInterval = 60.0

    // MARK: - Async Timer
    private var readingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks
    var onChapterChange: ((Chapter) -> Void)?
    var onReadingComplete: (() -> Void)?

    // MARK: - Computed Properties
    var currentWord: String {
        guard currentWordIndex < words.count else { return "" }
        return words[currentWordIndex]
    }

    var progress: Double {
        guard words.count > 0 else { return 0 }
        return Double(currentWordIndex) / Double(words.count)
    }

    var effectiveWPM: Int {
        isPlaying ? currentSoftStartWPM : wordsPerMinute
    }
    
    private var isTaskRunning: Bool {
        readingTask != nil && !readingTask!.isCancelled
    }

    // MARK: - Initialization
    init() {
        setupBindings()
    }
    
    deinit {
        readingTask?.cancel()
    }

    private func setupBindings() {
        $wordsPerMinute
            .sink { _ in
                // WPM changes are handled dynamically in the reading loop
            }
            .store(in: &cancellables)
        
        // Re-initialize stream mode when switching to it
        $readingMode
            .sink { [weak self] newMode in
                if newMode == .stream {
                    self?.initializeStreamMode()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Content Loading
    func loadContent(words: [String], chapters: [Chapter], startPosition: ReadingPosition) {
        self.words = words
        self.chapters = chapters
        
        // Invalidate line cache when new content is loaded
        invalidateLineCache()
        
        // Validate startPosition to prevent out-of-bounds access
        let validWordIndex = min(max(0, startPosition.wordIndex), max(0, words.count - 1))
        let validChapterIndex = min(max(0, startPosition.chapterIndex), max(0, chapters.count - 1))
        
        self.currentWordIndex = words.isEmpty ? 0 : validWordIndex
        self.currentChapterIndex = chapters.isEmpty ? 0 : validChapterIndex
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !words.isEmpty else { return }
        guard !isTaskRunning else { return }
        
        isPlaying = true
        softStartStartTime = Date()
        currentSoftStartWPM = max(50, Int(Double(wordsPerMinute) * softStartPercentage))
        
        startReadingLoop()
    }

    func pause() {
        isPlaying = false
        stopReadingLoop()
    }

    func stop() {
        isPlaying = false
        stopReadingLoop()
        currentWordIndex = 0
    }
    
    private func startReadingLoop() {
        readingTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled && self.isPlaying {
                // Calculate current effective WPM with soft start
                self.updateSoftStartWPM()
                
                let effectiveWPM = max(50, self.currentSoftStartWPM)
                let intervalNanoseconds = UInt64(60.0 / Double(effectiveWPM) * 1_000_000_000)
                
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                    
                    if !Task.isCancelled && self.isPlaying {
                        self.advanceWord()
                    }
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
    }
    
    private func updateSoftStartWPM() {
        guard let startTime = softStartStartTime else {
            currentSoftStartWPM = wordsPerMinute
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        if elapsed >= softStartDuration {
            currentSoftStartWPM = wordsPerMinute
            return
        }
        
        let progressRatio = elapsed / softStartDuration
        let targetWPM = Double(wordsPerMinute)
        let startWPM = targetWPM * softStartPercentage
        currentSoftStartWPM = Int(startWPM + (targetWPM - startWPM) * progressRatio)
    }
    
    private func stopReadingLoop() {
        readingTask?.cancel()
        readingTask = nil
    }

    private func advanceWord() {
        guard currentWordIndex < words.count - 1 else {
            pause()
            onReadingComplete?()
            return
        }

        // Update chapter index silently (no pause)
        if let chapter = chapters.first(where: { $0.startWordIndex == currentWordIndex + 1 }) {
            currentChapterIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? currentChapterIndex
        }

        currentWordIndex += 1
    }

    // MARK: - Stream Mode
    func initializeStreamMode() {
        // Stream mode now uses line-based rendering like scan mode
        // No special initialization needed
    }

    /// Get lines for stream mode - teleprompter style where text flows up
    /// Current line is centered, words appear one at a time on current line
    /// Uses same word wrapping as scan mode for consistency
    func getStreamLines(screenWidth: CGFloat, fontSize: CGFloat, availableHeight: CGFloat) -> (lines: [[String]], currentLineIndex: Int, wordIndexInLine: Int) {
        // Use same line building as scan mode
        return getLinesForScanMode(screenWidth: screenWidth, fontSize: fontSize, availableHeight: availableHeight)
    }

    // MARK: - Navigation
    func goToWord(at index: Int) {
        guard index >= 0 && index < words.count else { return }
        currentWordIndex = index
        updateCurrentChapter()
    }

    func goToChapter(_ chapter: Chapter) {
        currentWordIndex = chapter.startWordIndex
        if let index = chapters.firstIndex(where: { $0.id == chapter.id }) {
            currentChapterIndex = index
        }
    }

    func skipForward(words count: Int = 10) {
        let newIndex = min(words.count - 1, currentWordIndex + count)
        goToWord(at: newIndex)
    }

    func skipBackward(words count: Int = 10) {
        let newIndex = max(0, currentWordIndex - count)
        goToWord(at: newIndex)
    }

    private func updateCurrentChapter() {
        for (index, chapter) in chapters.enumerated() {
            if currentWordIndex >= chapter.startWordIndex && currentWordIndex <= chapter.endWordIndex {
                currentChapterIndex = index
                break
            }
        }
    }

    // MARK: - Settings
    func setSoftStartPercentage(_ percentage: Double) {
        softStartPercentage = max(0.1, min(1.0, percentage))
    }

    // MARK: - ORP Calculation
    func getORPIndex(for word: String) -> Int {
        let length = word.count
        guard length > 0 else { return 0 }

        // ORP is typically slightly left of center
        // For short words (1-3), it's the first letter
        // For medium words (4-6), it's around position 1-2
        // For longer words, it's around 1/3 of the way in
        switch length {
        case 1:
            return 0
        case 2...3:
            return 0
        case 4...5:
            return 1
        case 6...9:
            return 2
        case 10...13:
            return 3
        default:
            return length / 3
        }
    }

    // MARK: - Scan Mode Helpers
    
    /// Calculate estimated width of a word in points
    private func estimateWordWidth(_ word: String, fontSize: CGFloat) -> CGFloat {
        let charWidth = fontSize * 0.55
        let spaceWidth = fontSize * 0.3
        return CGFloat(word.count) * charWidth + spaceWidth
    }
    
    /// Build lines based on actual word widths to prevent overflow
    private func buildLinesWithWordWrapping(screenWidth: CGFloat, fontSize: CGFloat) -> [[String]] {
        let padding: CGFloat = 48
        let maxLineWidth = screenWidth - padding
        
        var lines: [[String]] = []
        var currentLine: [String] = []
        var currentLineWidth: CGFloat = 0
        
        for word in words {
            let wordWidth = estimateWordWidth(word, fontSize: fontSize)
            
            if currentLineWidth + wordWidth > maxLineWidth && !currentLine.isEmpty {
                // Start new line
                lines.append(currentLine)
                currentLine = [word]
                currentLineWidth = wordWidth
            } else {
                currentLine.append(word)
                currentLineWidth += wordWidth
            }
        }
        
        // Don't forget the last line
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines
    }
    
    /// Cache for word-to-line mapping
    private var cachedLines: [[String]]?
    private var cachedScreenWidth: CGFloat = 0
    private var cachedFontSize: CGFloat = 0
    
    func getLinesForScanMode(screenWidth: CGFloat, fontSize: CGFloat, availableHeight: CGFloat) -> (lines: [[String]], currentLineIndex: Int, wordIndexInLine: Int) {
        // Rebuild lines if parameters changed
        if cachedLines == nil || cachedScreenWidth != screenWidth || cachedFontSize != fontSize {
            cachedLines = buildLinesWithWordWrapping(screenWidth: screenWidth, fontSize: fontSize)
            cachedScreenWidth = screenWidth
            cachedFontSize = fontSize
        }
        
        guard let allLines = cachedLines, !allLines.isEmpty else {
            return ([], 0, 0)
        }
        
        let lineHeight = fontSize * 1.5
        let maxLines = max(3, Int(availableHeight / lineHeight))
        
        // Find which line contains the current word
        var wordCount = 0
        var currentLineNumber = 0
        var wordIndexInLine = 0
        
        for (lineIndex, line) in allLines.enumerated() {
            if wordCount + line.count > currentWordIndex {
                currentLineNumber = lineIndex
                wordIndexInLine = currentWordIndex - wordCount
                break
            }
            wordCount += line.count
        }
        
        // Center the current line in the view
        let linesAbove = maxLines / 2
        let startLine = max(0, currentLineNumber - linesAbove)
        let endLine = min(allLines.count, startLine + maxLines)
        
        let visibleLines = Array(allLines[startLine..<endLine])
        let currentLineIndexInArray = currentLineNumber - startLine
        
        return (visibleLines, currentLineIndexInArray, wordIndexInLine)
    }
    
    /// Invalidate line cache when content changes
    func invalidateLineCache() {
        cachedLines = nil
    }

    // MARK: - Bookmark Creation
    func startBookmarkCreation() {
        pause()
        isCreatingBookmark = true

        // Find paragraph boundaries (simple heuristic: look for sentence endings)
        let paragraphStart = findParagraphStart(from: currentWordIndex)
        let paragraphEnd = findParagraphEnd(from: currentWordIndex)

        bookmarkStartIndex = paragraphStart
        bookmarkEndIndex = paragraphEnd
    }

    func cancelBookmarkCreation() {
        isCreatingBookmark = false
    }

    func getBookmarkText() -> String {
        guard bookmarkStartIndex < bookmarkEndIndex,
              bookmarkEndIndex <= words.count else { return "" }
        return words[bookmarkStartIndex..<bookmarkEndIndex].joined(separator: " ")
    }

    private func findParagraphStart(from index: Int) -> Int {
        var start = index
        // Go back until we find a period, or reach the beginning
        while start > 0 {
            let word = words[start - 1]
            if word.hasSuffix(".") || word.hasSuffix("!") || word.hasSuffix("?") {
                break
            }
            start -= 1
        }
        return max(0, start)
    }

    private func findParagraphEnd(from index: Int) -> Int {
        var end = index
        // Go forward until we find a period, or reach the end
        while end < words.count {
            let word = words[end]
            if word.hasSuffix(".") || word.hasSuffix("!") || word.hasSuffix("?") {
                end += 1
                break
            }
            end += 1
        }
        return min(words.count, end)
    }

    // MARK: - Quick Bookmark (no popup)
    func quickBookmark() -> Bookmark? {
        guard !words.isEmpty else { return nil }
        
        let paragraphStart = findParagraphStart(from: currentWordIndex)
        let paragraphEnd = findParagraphEnd(from: currentWordIndex)
        
        guard paragraphStart < paragraphEnd, paragraphEnd <= words.count else { return nil }
        
        let text = words[paragraphStart..<paragraphEnd].joined(separator: " ")
        
        return Bookmark(
            bookId: UUID(), // Will be set by caller with actual book ID
            text: text,
            startWordIndex: paragraphStart,
            endWordIndex: paragraphEnd
        )
    }
    
    // MARK: - Reading Position
    func getCurrentPosition() -> ReadingPosition {
        return ReadingPosition(
            wordIndex: currentWordIndex,
            chapterIndex: currentChapterIndex,
            percentComplete: progress * 100
        )
    }
}
