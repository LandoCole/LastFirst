import Foundation
import Combine

/// Manages book content with chunked loading for memory efficiency
actor BookContentManager {
    
    // MARK: - Types
    
    struct ContentChunk {
        let startIndex: Int
        let endIndex: Int
        let words: [String]
    }
    
    enum ContentError: Error, LocalizedError {
        case fileNotFound
        case parseError(String)
        case invalidFileType
        case accessDenied
        case corruptedFile
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The book file could not be found."
            case .parseError(let message):
                return "Failed to parse the book: \(message)"
            case .invalidFileType:
                return "This file type is not supported."
            case .accessDenied:
                return "Cannot access the file. Please re-import the book."
            case .corruptedFile:
                return "The file appears to be corrupted."
            }
        }
    }
    
    // MARK: - Properties
    
    private let parser = DocumentParser()
    private var cachedChunks: [Int: ContentChunk] = [:]
    private var allWords: [String] = []
    private var chapters: [Chapter] = []
    private var images: [ParsedImage] = []
    private var metadata: (title: String, author: String, cover: Data?) = ("", "", nil)
    
    private let chunkSize: Int = 5000 // Words per chunk
    private var isFullyLoaded: Bool = false
    private var currentFilePath: String?
    
    // MARK: - Public Methods
    
    /// Load a book and return initial content
    func loadBook(at path: String, fileType: Book.FileType) async throws -> ParsedDocument {
        currentFilePath = path
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: path) else {
            throw ContentError.fileNotFound
        }
        
        // Parse based on file type
        let document: ParsedDocument
        do {
            switch fileType {
            case .epub:
                document = try await parser.parseEPub(at: path)
            case .pdf:
                document = try await parser.parsePDF(at: path)
            case .txt:
                document = try await parser.parseText(at: path)
            }
        } catch let error as DocumentParser.ParserError {
            switch error {
            case .invalidFile:
                throw ContentError.corruptedFile
            case .notImplemented:
                throw ContentError.invalidFileType
            case .parseError(let msg):
                throw ContentError.parseError(msg)
            }
        } catch {
            throw ContentError.parseError(error.localizedDescription)
        }
        
        // Store for chunked access
        self.allWords = document.words
        self.chapters = document.chapters
        self.images = document.images
        self.metadata = (document.title, document.author, document.coverImage)
        self.isFullyLoaded = true
        
        // Cache initial chunks
        cacheChunk(around: 0)
        
        return document
    }
    
    /// Get words for a specific range (with chunked loading)
    func getWords(from startIndex: Int, count: Int) -> [String] {
        guard isFullyLoaded else { return [] }
        
        let endIndex = min(startIndex + count, allWords.count)
        guard startIndex < endIndex else { return [] }
        
        return Array(allWords[startIndex..<endIndex])
    }
    
    /// Get all words (for smaller books or when needed)
    func getAllWords() -> [String] {
        return allWords
    }
    
    /// Get chapters
    func getChapters() -> [Chapter] {
        return chapters
    }
    
    /// Get total word count
    func getTotalWordCount() -> Int {
        return allWords.count
    }
    
    /// Preload chunks around a position for smooth reading
    func preloadChunks(around wordIndex: Int) {
        cacheChunk(around: wordIndex)
    }
    
    /// Clear cached content to free memory
    func clearCache() {
        cachedChunks.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func cacheChunk(around wordIndex: Int) {
        let chunkIndex = wordIndex / chunkSize
        
        // Cache current and adjacent chunks
        for offset in -1...1 {
            let targetChunk = chunkIndex + offset
            if targetChunk >= 0 && cachedChunks[targetChunk] == nil {
                let startIndex = targetChunk * chunkSize
                let endIndex = min(startIndex + chunkSize, allWords.count)
                
                if startIndex < allWords.count {
                    let chunk = ContentChunk(
                        startIndex: startIndex,
                        endIndex: endIndex,
                        words: Array(allWords[startIndex..<endIndex])
                    )
                    cachedChunks[targetChunk] = chunk
                }
            }
        }
        
        // Remove distant chunks to save memory (keep 5 chunks max)
        let chunksToKeep = Set((chunkIndex - 2)...(chunkIndex + 2))
        cachedChunks = cachedChunks.filter { chunksToKeep.contains($0.key) }
    }
}
