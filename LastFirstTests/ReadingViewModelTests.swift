import XCTest
@testable import LastFirst

final class ReadingViewModelTests: XCTestCase {
    
    var viewModel: ReadingViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = ReadingViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    // MARK: - ORP Calculation Tests
    
    func testORPIndex_singleCharacterWord() {
        // Single character words should have ORP at index 0
        XCTAssertEqual(viewModel.getORPIndex(for: "I"), 0)
        XCTAssertEqual(viewModel.getORPIndex(for: "a"), 0)
    }
    
    func testORPIndex_twoCharacterWord() {
        // 2-character words should have ORP at index 0
        XCTAssertEqual(viewModel.getORPIndex(for: "is"), 0)
        XCTAssertEqual(viewModel.getORPIndex(for: "to"), 0)
    }
    
    func testORPIndex_threeCharacterWord() {
        // 3-character words should have ORP at index 0
        XCTAssertEqual(viewModel.getORPIndex(for: "the"), 0)
        XCTAssertEqual(viewModel.getORPIndex(for: "and"), 0)
    }
    
    func testORPIndex_fourToFiveCharacterWord() {
        // 4-5 character words should have ORP at index 1
        XCTAssertEqual(viewModel.getORPIndex(for: "word"), 1)
        XCTAssertEqual(viewModel.getORPIndex(for: "hello"), 1)
        XCTAssertEqual(viewModel.getORPIndex(for: "quick"), 1)
    }
    
    func testORPIndex_sixToNineCharacterWord() {
        // 6-9 character words should have ORP at index 2
        XCTAssertEqual(viewModel.getORPIndex(for: "simple"), 2)
        XCTAssertEqual(viewModel.getORPIndex(for: "reading"), 2)
        XCTAssertEqual(viewModel.getORPIndex(for: "wonderful"), 2)
    }
    
    func testORPIndex_tenToThirteenCharacterWord() {
        // 10-13 character words should have ORP at index 3
        XCTAssertEqual(viewModel.getORPIndex(for: "understand"), 3)
        XCTAssertEqual(viewModel.getORPIndex(for: "comprehension"), 3)
    }
    
    func testORPIndex_longWord() {
        // Long words (14+) should have ORP at length/3
        let word = "internationalization" // 20 characters
        XCTAssertEqual(viewModel.getORPIndex(for: word), 6) // 20/3 = 6
    }
    
    func testORPIndex_emptyWord() {
        // Empty word should return 0
        XCTAssertEqual(viewModel.getORPIndex(for: ""), 0)
    }
    
    // MARK: - Content Loading Tests
    
    func testLoadContent_setsWordsCorrectly() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        let chapters: [Chapter] = []
        
        viewModel.loadContent(tokens: tokens, chapters: chapters, startTokenIndex: 0)
        
        XCTAssertEqual(viewModel.words.count, 4)
        XCTAssertEqual(viewModel.currentWord, "The")
    }
    
    func testLoadContent_setsStartPosition() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 2)
        
        XCTAssertEqual(viewModel.currentWordIndex, 2)
        XCTAssertEqual(viewModel.currentWord, "brown")
    }
    
    // MARK: - Progress Calculation Tests
    
    func testProgress_atStart() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 0)
        
        XCTAssertEqual(viewModel.progress, 0.0)
    }
    
    func testProgress_atMiddle() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 2)
        
        XCTAssertEqual(viewModel.progress, 0.5)
    }
    
    func testProgress_emptyContent() {
        viewModel.loadContent(tokens: [], chapters: [], startTokenIndex: 0)
        
        XCTAssertEqual(viewModel.progress, 0.0)
    }
    
    // MARK: - Navigation Tests
    
    func testGoToWord_validIndex() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 0)
        
        viewModel.goToWord(at: 2)
        
        XCTAssertEqual(viewModel.currentWordIndex, 2)
        XCTAssertEqual(viewModel.currentWord, "brown")
    }
    
    func testGoToWord_invalidNegativeIndex() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 1)
        
        viewModel.goToWord(at: -1)
        
        // Should not change
        XCTAssertEqual(viewModel.currentWordIndex, 1)
    }
    
    func testGoToWord_invalidLargeIndex() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 1)
        
        viewModel.goToWord(at: 100)
        
        // Should not change
        XCTAssertEqual(viewModel.currentWordIndex, 1)
    }
    
    func testSkipForward() {
        let words = Array(repeating: "word", count: 20)
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 5)
        
        viewModel.skipForward(words: 3)
        
        XCTAssertEqual(viewModel.currentWordIndex, 8)
    }
    
    func testSkipForward_clampsToEnd() {
        let words = Array(repeating: "word", count: 10)
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 8)
        
        viewModel.skipForward(words: 10)
        
        XCTAssertEqual(viewModel.currentWordIndex, 9) // Last valid index
    }
    
    func testSkipBackward() {
        let words = Array(repeating: "word", count: 20)
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 10)
        
        viewModel.skipBackward(words: 3)
        
        XCTAssertEqual(viewModel.currentWordIndex, 7)
    }
    
    func testSkipBackward_clampsToStart() {
        let words = Array(repeating: "word", count: 10)
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 2)
        
        viewModel.skipBackward(words: 10)
        
        XCTAssertEqual(viewModel.currentWordIndex, 0)
    }
    
    // MARK: - Playback State Tests
    
    func testInitialState_isPaused() {
        XCTAssertTrue(viewModel.isPaused)
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    func testPlay_withEmptyContent_doesNotStart() {
        viewModel.loadContent(tokens: [], chapters: [], startTokenIndex: 0)
        
        viewModel.play()
        
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    func testPlay_withContent_startsPlaying() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 0)
        
        viewModel.play()
        
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertFalse(viewModel.isPaused)
        
        // Clean up
        viewModel.pause()
    }
    
    func testPause_stopsPlaying() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 0)
        
        viewModel.play()
        viewModel.pause()
        
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertTrue(viewModel.isPaused)
    }
    
    func testStop_resetsToBeginning() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 2)
        
        viewModel.play()
        viewModel.stop()
        
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertTrue(viewModel.isPaused)
        XCTAssertEqual(viewModel.currentWordIndex, 0)
    }
    
    // MARK: - Bookmark Creation Tests
    
    func testStartBookmarkCreation_pausesPlayback() {
        let words = ["The", "quick", "brown", "fox"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 0)
        
        viewModel.play()
        viewModel.startBookmarkCreation()
        
        XCTAssertTrue(viewModel.isCreatingBookmark)
        XCTAssertTrue(viewModel.isPaused)
    }
    
    func testCancelBookmarkCreation() {
        viewModel.startBookmarkCreation()
        viewModel.cancelBookmarkCreation()
        
        XCTAssertFalse(viewModel.isCreatingBookmark)
    }
    
    // MARK: - Reading Position Tests
    
    func testGetCurrentProgress() {
        let words = Array(repeating: "word", count: 100)
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        viewModel.loadContent(tokens: tokens, chapters: [], startTokenIndex: 50)
        
        let progress = viewModel.getCurrentProgress()
        
        XCTAssertEqual(progress.tokenIndex, 50)
        XCTAssertEqual(progress.percentComplete, 50.0)
    }
}
