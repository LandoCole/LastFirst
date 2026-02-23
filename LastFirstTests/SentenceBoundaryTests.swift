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
    
    // MARK: - Helper to test paragraph boundaries (via Bookmark)
    
    private func loadAndGetBookmarkText(words: [String], startIndex: Int) -> String {
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: startIndex)
        viewModel.startBookmarkCreation()
        return viewModel.getBookmarkText()
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
        let words = Array(repeating: "word", count: 30)
        let text = loadAndGetBookmarkText(words: words, startIndex: 0)
        XCTAssertFalse(text.isEmpty)
    }
    
    func testSentenceEnd_atEndOfContent() {
        let words = ["Last", "word"]
        let text = loadAndGetBookmarkText(words: words, startIndex: 0)
        XCTAssertEqual(text, "Last word")
    }
    
    func testEmptyContent_streamMode() {
        viewModel.loadContent(tokens: [], chapters: [], startTokenIndex: 0)
        viewModel.startBookmarkCreation()
        XCTAssertEqual(viewModel.getBookmarkText(), "")
    }
}
