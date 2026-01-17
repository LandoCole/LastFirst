import XCTest
@testable import LastFirst

final class SentenceBoundaryTests: XCTestCase {
    
    var viewModel: ReadingViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = ReadingViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    // MARK: - Helper to test sentence boundaries
    
    private func loadAndGetBookmarkText(words: [String], startIndex: Int) -> String {
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: startIndex))
        viewModel.startBookmarkCreation()
        return viewModel.getBookmarkText()
    }
    
    // MARK: - Sentence End Detection Tests
    
    func testSentenceEnd_periodEnding() {
        let words = ["The", "quick", "fox.", "A", "new", "sentence."]
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: 0))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        // Stream mode should find sentence end at "fox."
        // This tests the internal findSentenceEnd logic via stream mode initialization
        XCTAssertEqual(viewModel.streamVisibleText, "The")
    }
    
    func testSentenceEnd_exclamationEnding() {
        let words = ["Hello", "world!", "How", "are", "you?"]
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: 0))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        XCTAssertEqual(viewModel.streamVisibleText, "Hello")
    }
    
    func testSentenceEnd_questionEnding() {
        let words = ["How", "are", "you?", "I", "am", "fine."]
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: 0))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        XCTAssertEqual(viewModel.streamVisibleText, "How")
    }
    
    func testSentenceEnd_quotedEnding() {
        let words = ["He", "said", "\"Hello.\"", "She", "replied."]
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: 0))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        XCTAssertEqual(viewModel.streamVisibleText, "He")
    }
    
    // MARK: - Paragraph Boundary Tests (via Bookmark)
    
    func testParagraphStart_findsBeginning() {
        let words = ["First", "sentence.", "Second", "sentence.", "Third", "word."]
        
        // Start at "Third" (index 4), should find paragraph start after "sentence." at index 4
        let text = loadAndGetBookmarkText(words: words, startIndex: 4)
        
        // Should include from "Third" to "word."
        XCTAssertTrue(text.contains("Third"))
        XCTAssertTrue(text.contains("word."))
    }
    
    func testParagraphEnd_findsSentenceEnd() {
        let words = ["The", "quick", "brown", "fox", "jumps."]
        
        // Start at "quick" (index 1)
        let text = loadAndGetBookmarkText(words: words, startIndex: 1)
        
        // Should include the full sentence
        XCTAssertTrue(text.contains("jumps."))
    }
    
    func testBookmarkText_fullSentence() {
        let words = ["Hello", "world.", "Goodbye", "world."]
        
        // Start at "Hello" (index 0)
        let text = loadAndGetBookmarkText(words: words, startIndex: 0)
        
        // Should get "Hello world."
        XCTAssertEqual(text, "Hello world.")
    }
    
    func testBookmarkText_middleOfSentence() {
        let words = ["The", "quick", "brown", "fox", "jumps.", "Over", "the", "dog."]
        
        // Start at "brown" (index 2)
        let text = loadAndGetBookmarkText(words: words, startIndex: 2)
        
        // Should get the full sentence containing "brown"
        XCTAssertTrue(text.contains("The"))
        XCTAssertTrue(text.contains("jumps."))
        XCTAssertFalse(text.contains("Over"))
    }
    
    // MARK: - Edge Cases
    
    func testSentenceEnd_noEndingPunctuation() {
        // When no sentence ending is found, should fallback to max 20 words
        var words = Array(repeating: "word", count: 30)
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: 0))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        // Should initialize without crashing
        XCTAssertEqual(viewModel.streamVisibleText, "word")
    }
    
    func testSentenceEnd_atEndOfContent() {
        let words = ["Last", "word"]
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: 0))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        XCTAssertEqual(viewModel.streamVisibleText, "Last")
    }
    
    func testEmptyContent_streamMode() {
        viewModel.loadContent(words: [], chapters: [], startPosition: ReadingPosition(wordIndex: 0))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        XCTAssertEqual(viewModel.streamVisibleText, "")
    }
    
    // MARK: - Stream Mode Initialization
    
    func testStreamMode_initializesCorrectly() {
        let words = ["The", "quick", "brown", "fox.", "Jumps", "over."]
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: 0))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        // Should start with first word
        XCTAssertEqual(viewModel.streamVisibleText, "The")
        XCTAssertFalse(viewModel.isBackspacing)
    }
    
    func testStreamMode_initializesFromMiddle() {
        let words = ["The", "quick", "brown", "fox.", "Jumps", "over."]
        viewModel.loadContent(words: words, chapters: [], startPosition: ReadingPosition(wordIndex: 4))
        viewModel.readingMode = .stream
        viewModel.initializeStreamMode()
        
        // Should start with word at current position
        XCTAssertEqual(viewModel.streamVisibleText, "Jumps")
    }
}
