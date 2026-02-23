import Foundation
import SwiftUI
import Combine

@MainActor
class ReadingViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isPlaying: Bool = false
    @Published var currentWordIndex: Int = 0
    @Published var wordsPerMinute: Int = 300
    @Published var readingMode: ReadingMode = .spritz
    @Published var isDialPushedDown: Bool = false
    @Published private(set) var isInParagraphBreath: Bool = false
    @Published var activeTitleCard: TitleCard? = nil

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
    @Published private(set) var tokens: [Token] = []
    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var blocks: [TextBlock] = []
    @Published private(set) var currentChapterIndex: Int = 0

    // MARK: - Structural Token Tracking
    struct TitleCard: Equatable {
        var title: String
        var subtitle: String?
        var epigraph: String?
    }

    private var paragraphEndWordIndexSet: Set<Int> = []
    private var titleCardByWordIndex: [Int: TitleCard] = [:]
    private var pendingWordIndexAfterTitleCard: Int? = nil

    private var wordTokenIndexByWordIndex: [Int] = []
    private var wordIndexByTokenIndex: [Int?] = []

    struct PausedWord: Identifiable, Equatable {
        var id: Int { wordIndex }
        var wordIndex: Int
        var text: String
    }

    enum PausedDisplayLineKind: Equatable {
        case text([PausedWord])
        case title(String, TokenKind)
        case blank
        case listItem([PausedWord], bullet: String)
        case blockquote([PausedWord])
        case codeBlock(String)
        case image(altText: String)
    }

    struct PausedDisplayLine: Identifiable, Equatable {
        var id: Int
        var kind: PausedDisplayLineKind
    }

    // MARK: - Soft Start
    private var softStartPercentage: Double = 0.6
    private var currentSoftStartWPM: Int = 0
    private var softStartStartTime: Date?
    private let softStartDuration: TimeInterval = 60.0

    // MARK: - Paragraph Breath
    private var paragraphBreathMs: Int = 0

    // MARK: - Async Timer
    private var readingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Metrics
    var metricsTracker: ReadingMetricsTracker?

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

    var currentChapter: Chapter? {
        guard !chapters.isEmpty, currentChapterIndex >= 0, currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    var chapterProgress: Double {
        guard let chapter = currentChapter else { return 0 }
        let chapterWordCount = chapter.endWordIndex - chapter.startWordIndex
        guard chapterWordCount > 0 else { return 0 }
        let positionInChapter = currentWordIndex - chapter.startWordIndex
        return Double(max(0, positionInChapter)) / Double(chapterWordCount)
    }

    var chapterTimeRemaining: TimeInterval {
        guard let chapter = currentChapter, wordsPerMinute > 0 else { return 0 }
        let remainingWords = max(0, chapter.endWordIndex - currentWordIndex)
        return Double(remainingWords) / Double(wordsPerMinute) * 60.0
    }

    func setProgress(_ progress: Double, chapterMode: Bool) {
        let clamped = max(0, min(1, progress))
        if chapterMode {
            guard let chapter = currentChapter else { return }
            let chapterWordCount = chapter.endWordIndex - chapter.startWordIndex
            let targetWord = chapter.startWordIndex + Int(clamped * Double(chapterWordCount))
            goToWord(at: min(targetWord, max(0, chapter.endWordIndex - 1)))
        } else {
            let targetWord = Int(clamped * Double(max(1, words.count - 1)))
            goToWord(at: targetWord)
        }
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
    func loadContent(tokens: [Token], chapters: [Chapter], blocks: [TextBlock] = [], startTokenIndex: Int) {
        self.tokens = tokens
        self.chapters = chapters
        self.blocks = blocks

        rebuildWordIndexMappings(tokens: tokens)
        
        // Invalidate line cache when new content is loaded
        invalidateLineCache()
        
        let computedStartWordIndex = wordIndexFromTokenIndex(startTokenIndex)
        let validWordIndex = min(max(0, computedStartWordIndex), max(0, words.count - 1))
        self.currentWordIndex = words.isEmpty ? 0 : validWordIndex
        updateCurrentChapter()
    }

    private func rebuildWordIndexMappings(tokens: [Token]) {
        var wordCount = 0

        var words: [String] = []
        words.reserveCapacity(tokens.count)

        wordTokenIndexByWordIndex = []
        wordIndexByTokenIndex = Array(repeating: nil, count: tokens.count)

        paragraphEndWordIndexSet = []
        titleCardByWordIndex = [:]
        pendingWordIndexAfterTitleCard = nil
        activeTitleCard = nil

        var pendingChapterTitle: String? = nil

        for (tokenIndex, token) in tokens.enumerated() {
            switch token.kind {
            case .chapterTitle:
                pendingChapterTitle = token.text
            case .paragraphBreak:
                if wordCount > 0 {
                    paragraphEndWordIndexSet.insert(wordCount - 1)
                }
            case .word, .footnoteRef:
                if let title = pendingChapterTitle {
                    titleCardByWordIndex[wordCount] = TitleCard(title: title, subtitle: nil, epigraph: nil)
                    pendingChapterTitle = nil
                }

                words.append(token.text)
                wordTokenIndexByWordIndex.append(tokenIndex)
                wordIndexByTokenIndex[tokenIndex] = wordCount
                wordCount += 1
            case .listBullet:
                // Structural marker — not counted as a word, but included in display
                break
            case .imageAlt:
                // Image alt text — not counted as a word for reading progress
                break
            default:
                break
            }
        }

        self.words = words
    }

    private func wordIndexFromTokenIndex(_ tokenIndex: Int) -> Int {
        guard !wordIndexByTokenIndex.isEmpty else { return 0 }

        let clamped = min(max(0, tokenIndex), wordIndexByTokenIndex.count - 1)
        if let exact = wordIndexByTokenIndex[clamped] { return exact }

        for i in clamped..<wordIndexByTokenIndex.count {
            if let v = wordIndexByTokenIndex[i] { return v }
        }

        return max(0, words.count - 1)
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

        if let pending = pendingWordIndexAfterTitleCard {
            activeTitleCard = nil
            pendingWordIndexAfterTitleCard = nil
            currentWordIndex = min(max(0, pending), max(0, words.count - 1))
            updateCurrentChapter()
        }
        
        isPlaying = true
        metricsTracker?.resume()
        softStartStartTime = Date()
        currentSoftStartWPM = max(50, Int(Double(wordsPerMinute) * softStartPercentage))

        startReadingLoop()
    }

    func pause() {
        isPlaying = false
        metricsTracker?.pause()
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
                        await self.advanceWord()
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

    private func advanceWord() async {
        guard isPlaying, !Task.isCancelled else { return }

        guard currentWordIndex < words.count - 1 else {
            pause()
            onReadingComplete?()
            return
        }

        let nextWordIndex = currentWordIndex + 1

        if (readingMode == .spritz || readingMode == .stream), let titleCard = titleCardByWordIndex[nextWordIndex] {
            pendingWordIndexAfterTitleCard = nextWordIndex
            activeTitleCard = titleCard
            pause()
            return
        }

        if isPlaying, paragraphBreathMs > 0 && paragraphEndWordIndexSet.contains(currentWordIndex) {
            isInParagraphBreath = true
            do {
                try await Task.sleep(nanoseconds: UInt64(paragraphBreathMs) * 1_000_000)
            } catch {
                isInParagraphBreath = false
                return
            }
            if !isPlaying || Task.isCancelled {
                isInParagraphBreath = false
                return
            }
            isInParagraphBreath = false
        }

        // Update chapter index silently (no pause)
        if let chapter = chapters.first(where: { $0.startWordIndex == nextWordIndex }) {
            currentChapterIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? currentChapterIndex
            metricsTracker?.recordChapter(chapter.title)
        }

        currentWordIndex = nextWordIndex
        metricsTracker?.recordWordAdvance()
        if nextWordIndex < wordTokenIndexByWordIndex.count {
            metricsTracker?.recordTokenIndex(wordTokenIndexByWordIndex[nextWordIndex])
        }
    }

    // MARK: - Stream Mode
    func initializeStreamMode() {
        // Stream mode now uses line-based rendering like scan mode
        // No special initialization needed
    }

    /// Get lines for stream mode - teleprompter style where text flows up
    /// Current line is centered, words appear one at a time on current line
    /// Uses same word wrapping as scan mode for consistency
    func getStreamLines(screenWidth: CGFloat, fontSize: CGFloat, availableHeight: CGFloat) -> (lines: [WrappedLine], currentLineIndex: Int, wordIndexInLine: Int) {
        // Use same line building as scan mode
        return getWrappedLines(screenWidth: screenWidth, fontSize: fontSize, availableHeight: availableHeight)
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

    func goToTokenIndex(_ tokenIndex: Int) {
        let wordIndex = wordIndexFromTokenIndex(tokenIndex)
        goToWord(at: wordIndex)
    }

    func goToNextChapter() {
        guard !chapters.isEmpty else { return }
        if let nextChapter = chapters.first(where: { $0.startWordIndex > currentWordIndex }) {
            goToChapter(nextChapter)
        }
    }

    func goToPreviousChapter() {
        guard !chapters.isEmpty else { return }
        // If we're past the start of the current chapter, go to its start first
        if let current = chapters.last(where: { $0.startWordIndex <= currentWordIndex }),
           currentWordIndex > current.startWordIndex + 5 {
            goToChapter(current)
            return
        }
        // Otherwise go to the previous chapter
        if let currentIdx = chapters.lastIndex(where: { $0.startWordIndex <= currentWordIndex }),
           currentIdx > 0 {
            goToChapter(chapters[currentIdx - 1])
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

    func rewindToSentenceStart() {
        pause()
        guard currentWordIndex > 0 else { return }

        let prevWord = words[currentWordIndex - 1]
        let atSentenceBoundary = prevWord.hasSuffix(".") || prevWord.hasSuffix("!") || prevWord.hasSuffix("?")

        if atSentenceBoundary {
            let target = findParagraphStart(from: currentWordIndex - 1)
            goToWord(at: target)
        } else {
            let target = findParagraphStart(from: currentWordIndex)
            goToWord(at: target)
        }
    }

    func forwardToNextSentenceEnd() {
        pause()
        guard currentWordIndex < words.count else { return }
        let target = findParagraphEnd(from: currentWordIndex)
        goToWord(at: min(target, words.count - 1))
    }

    func advanceOneWord() {
        guard currentWordIndex < words.count - 1 else { return }
        currentWordIndex += 1
        updateCurrentChapter()
    }

    func rewindOneWord() {
        guard currentWordIndex > 0 else { return }
        currentWordIndex -= 1
        updateCurrentChapter()
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

    func setParagraphBreathMs(_ ms: Int) {
        paragraphBreathMs = max(0, min(1000, ms))
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

    struct WrappedLine: Equatable {
        var words: [String]
        var isBlank: Bool
        var blockKind: BlockKind

        static func blank() -> WrappedLine {
            WrappedLine(words: [], isBlank: true, blockKind: .paragraph)
        }

        static func text(_ words: [String], kind: BlockKind = .paragraph) -> WrappedLine {
            WrappedLine(words: words, isBlank: false, blockKind: kind)
        }
    }
    
    /// Calculate estimated width of a word in points
    private func estimateWordWidth(_ word: String, fontSize: CGFloat, wordSpacing: CGFloat = 0, letterSpacing: CGFloat = 0) -> CGFloat {
        let charWidth = fontSize * 0.50
        let trackingPerChar = fontSize * letterSpacing
        let spaceWidth = fontSize * 0.28
        let interWordSpacing = fontSize * wordSpacing
        return CGFloat(word.count) * (charWidth + trackingPerChar) + spaceWidth + interWordSpacing
    }
    
    /// Build lines based on actual word widths to prevent overflow
    private func buildLinesWithWordWrapping(screenWidth: CGFloat, fontSize: CGFloat) -> [WrappedLine] {
        let padding: CGFloat = 48
        let maxLineWidth = screenWidth - padding
        
        var lines: [WrappedLine] = []
        var currentLine: [String] = []
        var currentLineWidth: CGFloat = 0

        func flushLineIfNeeded() {
            guard !currentLine.isEmpty else { return }
            lines.append(.text(currentLine))
            currentLine = []
            currentLineWidth = 0
        }

        func appendBlankLineIfNeeded() {
            if lines.last?.isBlank == true { return }
            lines.append(.blank())
        }

        for token in tokens {
            switch token.kind {
            case .word:
                let word = token.text
                let wordWidth = estimateWordWidth(word, fontSize: fontSize)

                if currentLineWidth + wordWidth > maxLineWidth && !currentLine.isEmpty {
                    flushLineIfNeeded()
                }

                currentLine.append(word)
                currentLineWidth += wordWidth

            case .paragraphBreak:
                flushLineIfNeeded()
                appendBlankLineIfNeeded()

            default:
                break
            }
        }
        
        // Don't forget the last line
        flushLineIfNeeded()
        
        return lines
    }
    
    /// Cache for word-to-line mapping
    private var cachedLines: [WrappedLine]?
    private var cachedScreenWidth: CGFloat = 0
    private var cachedFontSize: CGFloat = 0
    
    func getWrappedLines(screenWidth: CGFloat, fontSize: CGFloat, availableHeight: CGFloat) -> (lines: [WrappedLine], currentLineIndex: Int, wordIndexInLine: Int) {
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
            if line.isBlank { continue }
            if wordCount + line.words.count > currentWordIndex {
                currentLineNumber = lineIndex
                wordIndexInLine = currentWordIndex - wordCount
                break
            }
            wordCount += line.words.count
        }
        
        // Center the current line in the view
        let linesAbove = maxLines / 2
        let startLine = max(0, currentLineNumber - linesAbove)
        let endLine = min(allLines.count, startLine + maxLines)

        let visibleLines = Array(allLines[startLine..<endLine])
        let currentLineIndexInArray = currentLineNumber - startLine

        return (visibleLines, currentLineIndexInArray, wordIndexInLine)
    }

    func getAllWrappedLines(screenWidth: CGFloat, fontSize: CGFloat) -> [WrappedLine] {
        if cachedLines == nil || cachedScreenWidth != screenWidth || cachedFontSize != fontSize {
            cachedLines = buildLinesWithWordWrapping(screenWidth: screenWidth, fontSize: fontSize)
            cachedScreenWidth = screenWidth
            cachedFontSize = fontSize
        }
        return cachedLines ?? []
    }

    func getPausedDisplayLines(
        screenWidth: CGFloat,
        fontSize: CGFloat,
        horizontalPadding: CGFloat = 48,
        wordSpacing: CGFloat = 0,
        letterSpacing: CGFloat = 0
    ) -> (lines: [PausedDisplayLine], currentLineId: Int) {
        let maxLineWidth = screenWidth - horizontalPadding

        var lines: [PausedDisplayLine] = []
        lines.reserveCapacity(max(32, words.count / 8))

        var currentLineWords: [PausedWord] = []
        var currentLineWidth: CGFloat = 0
        var currentWordCount = 0
        var currentLineContainsPausedWord = false
        var pausedLineId: Int = 0

        func flushTextLine() {
            guard !currentLineWords.isEmpty else { return }
            let lineId = lines.count
            lines.append(PausedDisplayLine(id: lineId, kind: .text(currentLineWords)))
            if currentLineContainsPausedWord {
                pausedLineId = lineId
            }
            currentLineWords = []
            currentLineWidth = 0
            currentLineContainsPausedWord = false
        }

        func appendBlankLine() {
            let lineId = lines.count
            lines.append(PausedDisplayLine(id: lineId, kind: .blank))
        }

        func appendTitleLine(_ title: String, kind: TokenKind) {
            let lineId = lines.count
            lines.append(PausedDisplayLine(id: lineId, kind: .title(title, kind)))
        }

        // Track current block for structural awareness
        var currentBlockIndex = 0
        var currentBlockKind: BlockKind = .paragraph

        for token in tokens {
            // Update block context
            if token.blockIndex != currentBlockIndex && token.blockIndex < (tokens.last?.blockIndex ?? 0) + 1 {
                if token.blockIndex < blocks.count {
                    currentBlockKind = blocks[token.blockIndex].kind
                }
                currentBlockIndex = token.blockIndex
            }

            switch token.kind {
            case .chapterTitle, .sectionTitle, .epigraph:
                flushTextLine()
                appendTitleLine(token.text, kind: token.kind)
                appendBlankLine()

            case .paragraphBreak:
                flushTextLine()
                appendBlankLine()

            case .listBullet:
                // List bullet is a structural marker — start new line but don't count as word
                flushTextLine()

            case .imageAlt:
                flushTextLine()
                let lineId = lines.count
                lines.append(PausedDisplayLine(id: lineId, kind: .image(altText: token.text)))
                appendBlankLine()

            case .word, .footnoteRef:
                let wordWidth = estimateWordWidth(token.text, fontSize: fontSize, wordSpacing: wordSpacing, letterSpacing: letterSpacing)
                if currentLineWidth + wordWidth > maxLineWidth && !currentLineWords.isEmpty {
                    flushTextLine()
                }

                if currentWordCount == currentWordIndex {
                    currentLineContainsPausedWord = true
                }

                currentLineWords.append(PausedWord(wordIndex: currentWordCount, text: token.text))
                currentLineWidth += wordWidth
                currentWordCount += 1

            case .punctuation:
                break
            }
        }

        flushTextLine()
        return (lines, pausedLineId)
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
    struct BookmarkDraft: Equatable {
        var text: String
        var startTokenIndex: Int
        var endTokenIndex: Int
    }

    func quickBookmarkDraft() -> BookmarkDraft? {
        guard !words.isEmpty else { return nil }

        let paragraphStart = findParagraphStart(from: currentWordIndex)
        let paragraphEnd = findParagraphEnd(from: currentWordIndex)

        guard paragraphStart < paragraphEnd, paragraphEnd <= words.count else { return nil }

        let text = words[paragraphStart..<paragraphEnd].joined(separator: " ")

        let startTokenIndex: Int = {
            if paragraphStart >= 0, paragraphStart < wordTokenIndexByWordIndex.count {
                return wordTokenIndexByWordIndex[paragraphStart]
            }
            return paragraphStart
        }()

        let endTokenIndex: Int = {
            let lastWordIndex = max(0, min(paragraphEnd - 1, wordTokenIndexByWordIndex.count - 1))
            if lastWordIndex >= 0, lastWordIndex < wordTokenIndexByWordIndex.count {
                return wordTokenIndexByWordIndex[lastWordIndex]
            }
            return max(0, paragraphEnd - 1)
        }()

        return BookmarkDraft(
            text: text,
            startTokenIndex: startTokenIndex,
            endTokenIndex: endTokenIndex
        )
    }
    
    // MARK: - Reading Position
    func getCurrentProgress() -> ReadingProgress {
        let tokenIndex: Int = {
            if currentWordIndex >= 0, currentWordIndex < wordTokenIndexByWordIndex.count {
                return wordTokenIndexByWordIndex[currentWordIndex]
            }
            return currentWordIndex
        }()
        return ReadingProgress(
            tokenIndex: tokenIndex,
            percentComplete: progress * 100
        )
    }
}
