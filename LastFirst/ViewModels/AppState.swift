import Foundation
import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published var library: [Book] {
        didSet { saveLibrary() }
    }
    @Published var bookmarks: [UUID: [Bookmark]] {
        didSet { saveBookmarks() }
    }
    @Published var savedImages: [UUID: [SavedImageMetadata]] {
        didSet { saveSavedImages() }
    }
    @Published var currentBook: Book?
    @Published var lastError: AppError?

    private let settingsKey = "app_settings"
    private let libraryKey = "library"
    private let bookmarksKey = "bookmarks"
    private let imagesKey = "saved_images_v2"
    private let imageStorage = ImageStorageManager.shared
    
    // MARK: - Error Types
    enum AppError: Error, LocalizedError {
        case persistenceError(String)
        case fileAccessError(String)
        case migrationError(String)
        
        var errorDescription: String? {
            switch self {
            case .persistenceError(let msg):
                return "Failed to save data: \(msg)"
            case .fileAccessError(let msg):
                return "File access error: \(msg)"
            case .migrationError(let msg):
                return "Migration error: \(msg)"
            }
        }
    }

    init() {
        self.settings = Self.loadSettings()
        self.library = Self.loadLibrary()
        self.bookmarks = Self.loadBookmarks()
        self.savedImages = Self.loadSavedImages()
        self.footnotes = Self.loadFootnotes()
        
        // Migrate old image data if needed
        migrateImageDataIfNeeded()
    }
    
    // MARK: - Migration
    private func migrateImageDataIfNeeded() {
        let migrationKey = "images_migrated_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        
        // Check for old format images and migrate them
        if let oldData = UserDefaults.standard.data(forKey: "saved_images"),
           let oldImages = try? JSONDecoder().decode([UUID: [SavedImage]].self, from: oldData) {
            
            for (bookId, images) in oldImages {
                for image in images {
                    // Save image data to file system
                    do {
                        try imageStorage.saveImage(image.imageData, imageId: image.id, bookId: bookId)
                        
                        // Create metadata entry
                        let metadata = SavedImageMetadata(
                            id: image.id,
                            bookId: image.bookId,
                            pageIndex: image.pageIndex,
                            wordIndex: image.wordIndex,
                            isSeen: image.isSeen,
                            isBookmarked: image.isBookmarked,
                            dateFound: image.dateFound
                        )
                        
                        if savedImages[bookId] == nil {
                            savedImages[bookId] = []
                        }
                        savedImages[bookId]?.append(metadata)
                    } catch {
                        lastError = .migrationError("Failed to migrate image: \(error.localizedDescription)")
                    }
                }
            }
            
            // Remove old data
            UserDefaults.standard.removeObject(forKey: "saved_images")
        }
        
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Settings
    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "app_settings") else {
            return AppSettings()
        }
        
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            print("[AppState] Failed to decode settings, using defaults: \(error)")
            return AppSettings()
        }
    }

    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: settingsKey)
        } catch {
            lastError = .persistenceError("Settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Library
    private static func loadLibrary() -> [Book] {
        guard let data = UserDefaults.standard.data(forKey: "library") else {
            return []
        }
        
        do {
            let library = try JSONDecoder().decode([Book].self, from: data)
            return library.sorted { ($0.lastOpened ?? $0.dateAdded) > ($1.lastOpened ?? $1.dateAdded) }
        } catch {
            print("[AppState] Failed to decode library: \(error)")
            return []
        }
    }

    private func saveLibrary() {
        do {
            let data = try JSONEncoder().encode(library)
            UserDefaults.standard.set(data, forKey: libraryKey)
        } catch {
            lastError = .persistenceError("Library: \(error.localizedDescription)")
        }
    }

    func addBook(_ book: Book) {
        library.insert(book, at: 0)
    }

    func updateBook(_ book: Book) {
        if let index = library.firstIndex(where: { $0.id == book.id }) {
            library[index] = book
        }
    }

    func deleteBook(_ book: Book) {
        library.removeAll { $0.id == book.id }
        bookmarks.removeValue(forKey: book.id)
        savedImages.removeValue(forKey: book.id)
        
        // Clean up file system images
        imageStorage.deleteAllImages(for: book.id)
        
        // Delete the book file itself
        try? FileManager.default.removeItem(atPath: book.filePath)
    }

    // MARK: - Bookmarks
    private static func loadBookmarks() -> [UUID: [Bookmark]] {
        guard let data = UserDefaults.standard.data(forKey: "bookmarks") else {
            return [:]
        }
        
        do {
            return try JSONDecoder().decode([UUID: [Bookmark]].self, from: data)
        } catch {
            print("[AppState] Failed to decode bookmarks: \(error)")
            return [:]
        }
    }

    private func saveBookmarks() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        } catch {
            lastError = .persistenceError("Bookmarks: \(error.localizedDescription)")
        }
    }

    func addBookmark(_ bookmark: Bookmark) {
        if bookmarks[bookmark.bookId] == nil {
            bookmarks[bookmark.bookId] = []
        }
        bookmarks[bookmark.bookId]?.append(bookmark)
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks[bookmark.bookId]?.removeAll { $0.id == bookmark.id }
    }

    func getBookmarks(for bookId: UUID) -> [Bookmark] {
        return bookmarks[bookId] ?? []
    }

    // MARK: - Saved Images (File-based storage)
    private static func loadSavedImages() -> [UUID: [SavedImageMetadata]] {
        guard let data = UserDefaults.standard.data(forKey: "saved_images_v2") else {
            return [:]
        }
        
        do {
            return try JSONDecoder().decode([UUID: [SavedImageMetadata]].self, from: data)
        } catch {
            print("[AppState] Failed to decode saved images metadata: \(error)")
            return [:]
        }
    }

    private func saveSavedImages() {
        do {
            let data = try JSONEncoder().encode(savedImages)
            UserDefaults.standard.set(data, forKey: imagesKey)
        } catch {
            lastError = .persistenceError("Images: \(error.localizedDescription)")
        }
    }

    func addSavedImage(_ image: SavedImage) {
        // Save image data to file system
        do {
            try imageStorage.saveImage(image.imageData, imageId: image.id, bookId: image.bookId)
            
            // Store only metadata in UserDefaults
            let metadata = SavedImageMetadata(
                id: image.id,
                bookId: image.bookId,
                pageIndex: image.pageIndex,
                wordIndex: image.wordIndex,
                isSeen: image.isSeen,
                isBookmarked: image.isBookmarked,
                dateFound: image.dateFound
            )
            
            if savedImages[image.bookId] == nil {
                savedImages[image.bookId] = []
            }
            savedImages[image.bookId]?.append(metadata)
        } catch {
            lastError = .fileAccessError("Failed to save image: \(error.localizedDescription)")
        }
    }

    func markImageAsSeen(_ imageId: UUID, bookId: UUID) {
        if let index = savedImages[bookId]?.firstIndex(where: { $0.id == imageId }) {
            savedImages[bookId]?[index].isSeen = true
        }
    }

    func toggleImageBookmark(_ imageId: UUID, bookId: UUID) {
        if let index = savedImages[bookId]?.firstIndex(where: { $0.id == imageId }) {
            savedImages[bookId]?[index].isBookmarked.toggle()
        }
    }

    func getUnseenImageCount(for bookId: UUID) -> Int {
        return savedImages[bookId]?.filter { !$0.isSeen }.count ?? 0
    }

    func getSavedImages(for bookId: UUID) -> [SavedImage] {
        guard let metadataList = savedImages[bookId] else { return [] }
        
        return metadataList.compactMap { metadata in
            guard let imageData = imageStorage.loadImage(imageId: metadata.id, bookId: bookId) else {
                return nil
            }
            
            return SavedImage(
                id: metadata.id,
                bookId: metadata.bookId,
                imageData: imageData,
                pageIndex: metadata.pageIndex,
                wordIndex: metadata.wordIndex,
                isSeen: metadata.isSeen,
                isBookmarked: metadata.isBookmarked,
                dateFound: metadata.dateFound
            )
        }
    }
    
    func deleteImage(_ imageId: UUID, bookId: UUID) {
        imageStorage.deleteImage(imageId: imageId, bookId: bookId)
        savedImages[bookId]?.removeAll { $0.id == imageId }
    }
    
    // MARK: - Cover Images
    func getCoverImage(for bookId: UUID) -> Data? {
        return imageStorage.loadCoverImage(for: bookId)
    }
    
    // MARK: - Footnotes
    @Published var footnotes: [UUID: [Footnote]] = [:] {
        didSet { saveFootnotes() }
    }
    
    private let footnotesKey = "footnotes"
    
    private static func loadFootnotes() -> [UUID: [Footnote]] {
        guard let data = UserDefaults.standard.data(forKey: "footnotes") else {
            return [:]
        }
        
        do {
            return try JSONDecoder().decode([UUID: [Footnote]].self, from: data)
        } catch {
            print("[AppState] Failed to decode footnotes: \(error)")
            return [:]
        }
    }
    
    private func saveFootnotes() {
        do {
            let data = try JSONEncoder().encode(footnotes)
            UserDefaults.standard.set(data, forKey: footnotesKey)
        } catch {
            lastError = .persistenceError("Footnotes: \(error.localizedDescription)")
        }
    }
    
    func addFootnote(_ footnote: Footnote) {
        if footnotes[footnote.bookId] == nil {
            footnotes[footnote.bookId] = []
        }
        footnotes[footnote.bookId]?.append(footnote)
    }
    
    func getFootnotes(for bookId: UUID) -> [Footnote] {
        return footnotes[bookId] ?? []
    }
}
