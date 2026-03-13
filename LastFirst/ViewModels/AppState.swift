import Foundation
import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published var library: [LibraryItem] {
        didSet { saveLibrary() }
    }
    @Published var annotations: [UUID: [Annotation]] {
        didSet { saveAnnotations() }
    }
    @Published var savedImages: [UUID: [SavedImageMetadata]] {
        didSet { saveSavedImages() }
    }
    @Published var lastError: AppError?
    @Published var readingLists: [ReadingList] {
        didSet { saveReadingLists() }
    }
    @Published var isLoaded = false

    private let settingsKey = "app_settings"
    private let libraryKey = "library"
    private let annotationsKey = "annotations_v1"
    private let imagesKey = "saved_images_v2"
    private let readingListsKey = "reading_lists"
    private let imageStorage = ImageStorageManager.shared
    private var dominantColorCache: [UUID: UIColor] = [:]

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
        self.annotations = Self.loadAnnotations()
        self.savedImages = Self.loadSavedImages()
        self.footnotes = Self.loadFootnotes()
        self.readingLists = Self.loadReadingLists()

        // Migrate old image data if needed
        migrateImageDataIfNeeded()
        isLoaded = true
    }
    
    // MARK: - Migration
    private func migrateImageDataIfNeeded() {
        let migrationKey = "images_migrated_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

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
    private static func loadLibrary() -> [LibraryItem] {
        guard let data = UserDefaults.standard.data(forKey: "library") else {
            return []
        }
        
        do {
            let library = try JSONDecoder().decode([LibraryItem].self, from: data)
            return library.sorted { ($0.lastOpenedAt ?? $0.dateAdded) > ($1.lastOpenedAt ?? $1.dateAdded) }
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

    func addItem(_ item: LibraryItem) {
        library.insert(item, at: 0)
    }

    func updateItem(_ item: LibraryItem) {
        if let index = library.firstIndex(where: { $0.id == item.id }) {
            library[index] = item
        }
    }

    func deleteItem(_ item: LibraryItem) {
        library.removeAll { $0.id == item.id }
        annotations.removeValue(forKey: item.documentId)
        savedImages.removeValue(forKey: item.documentId)
        footnotes.removeValue(forKey: item.documentId)
        
        // Clean up file system images
        imageStorage.deleteAllImages(for: item.documentId)
        
        // Delete stored document snapshots
        Task {
            try? await DocumentStoreActor.shared.delete(documentId: item.documentId)
            try? await ResourceCacheActor.shared.delete(documentId: item.documentId)
        }
        
        // Delete the local file itself (web items have no local file)
        if case .localFile(let local) = item.source {
            try? FileManager.default.removeItem(at: local.fileURL)
        }
    }

    @MainActor
    func refreshLibraryMetadataFromStoreIfNeeded() async {
        guard !library.isEmpty else { return }

        for index in library.indices {
            let item = library[index]

            let needsTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.title == "Unknown Title"
            let needsAuthor = (item.author ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.author == "Unknown Author"
            guard needsTitle || needsAuthor else { continue }

            do {
                var updated = item

                let packages = try await DocumentStoreActor.shared.load(documentId: item.documentId)
                let manifest = packages.manifest
                let docTitle = manifest.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let docAuthor = manifest.authors.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if needsTitle, !docTitle.isEmpty {
                    updated.title = docTitle
                }
                if needsAuthor {
                    updated.author = docAuthor.isEmpty ? nil : docAuthor
                }

                if updated != item {
                    library[index] = updated
                }
            } catch {
                continue
            }
        }
    }

    // MARK: - Annotations
    private static func loadAnnotations() -> [UUID: [Annotation]] {
        guard let data = UserDefaults.standard.data(forKey: "annotations_v1") else {
            return [:]
        }
        
        do {
            return try JSONDecoder().decode([UUID: [Annotation]].self, from: data)
        } catch {
            print("[AppState] Failed to decode annotations: \(error)")
            return [:]
        }
    }

    private func saveAnnotations() {
        do {
            let data = try JSONEncoder().encode(annotations)
            UserDefaults.standard.set(data, forKey: annotationsKey)
        } catch {
            lastError = .persistenceError("Annotations: \(error.localizedDescription)")
        }
    }

    func addAnnotation(_ annotation: Annotation) {
        if annotations[annotation.documentId] == nil {
            annotations[annotation.documentId] = []
        }
        annotations[annotation.documentId]?.append(annotation)
    }

    func removeAnnotation(_ annotation: Annotation) {
        annotations[annotation.documentId]?.removeAll { $0.id == annotation.id }
    }

    func getAnnotations(for documentId: UUID) -> [Annotation] {
        return annotations[documentId] ?? []
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
            try imageStorage.saveImage(image.imageData, imageId: image.id, bookId: image.documentId)
            
            // Store only metadata in UserDefaults
            let metadata = SavedImageMetadata(
                id: image.id,
                documentId: image.documentId,
                pageIndex: image.pageIndex,
                wordIndex: image.wordIndex,
                isSeen: image.isSeen,
                isBookmarked: image.isBookmarked,
                dateFound: image.dateFound
            )
            
            if savedImages[image.documentId] == nil {
                savedImages[image.documentId] = []
            }
            savedImages[image.documentId]?.append(metadata)
        } catch {
            lastError = .fileAccessError("Failed to save image: \(error.localizedDescription)")
        }
    }

    func markImageAsSeen(_ imageId: UUID, documentId: UUID) {
        if let index = savedImages[documentId]?.firstIndex(where: { $0.id == imageId }) {
            savedImages[documentId]?[index].isSeen = true
        }
    }

    func toggleImageBookmark(_ imageId: UUID, documentId: UUID) {
        if let index = savedImages[documentId]?.firstIndex(where: { $0.id == imageId }) {
            savedImages[documentId]?[index].isBookmarked.toggle()
        }
    }

    func getUnseenImageCount(for documentId: UUID) -> Int {
        return savedImages[documentId]?.filter { !$0.isSeen }.count ?? 0
    }

    func getSavedImages(for documentId: UUID) -> [SavedImage] {
        guard let metadataList = savedImages[documentId] else { return [] }
        
        return metadataList.compactMap { metadata in
            guard let imageData = imageStorage.loadImage(imageId: metadata.id, bookId: documentId) else {
                return nil
            }
            
            return SavedImage(
                id: metadata.id,
                documentId: metadata.documentId,
                imageData: imageData,
                pageIndex: metadata.pageIndex,
                wordIndex: metadata.wordIndex,
                isSeen: metadata.isSeen,
                isBookmarked: metadata.isBookmarked,
                dateFound: metadata.dateFound
            )
        }
    }
    
    func deleteImage(_ imageId: UUID, documentId: UUID) {
        imageStorage.deleteImage(imageId: imageId, bookId: documentId)
        savedImages[documentId]?.removeAll { $0.id == imageId }
    }
    
    // MARK: - Cover Images
    func getCoverImage(for documentId: UUID) -> Data? {
        return imageStorage.loadCoverImage(for: documentId)
    }

    /// Returns the dominant color of the cover image, cached in memory.
    func getDominantCoverColor(for documentId: UUID) -> UIColor? {
        if let cached = dominantColorCache[documentId] { return cached }
        guard let data = getCoverImage(for: documentId),
              let image = UIImage(data: data),
              let color = image.dominantColor() else { return nil }
        dominantColorCache[documentId] = color
        return color
    }

    /// Load any pending images that were extracted during document ingestion
    func loadPendingImages(for documentId: UUID) {
        let key = "pending_images_\(documentId.uuidString)"
        guard let pendingImages = UserDefaults.standard.array(forKey: key) as? [[String: Any]] else {
            return
        }

        for imageInfo in pendingImages {
            guard let idString = imageInfo["id"] as? String,
                  let imageId = UUID(uuidString: idString),
                  let pageIndex = imageInfo["pageIndex"] as? Int,
                  let wordIndex = imageInfo["wordIndex"] as? Int,
                  let timestamp = imageInfo["dateFound"] as? TimeInterval else {
                continue
            }

            // Check if we already have this image in metadata
            if savedImages[documentId]?.contains(where: { $0.id == imageId }) == true {
                continue
            }

            // Add metadata (image data is already saved to file system)
            let metadata = SavedImageMetadata(
                id: imageId,
                documentId: documentId,
                pageIndex: pageIndex,
                wordIndex: wordIndex,
                isSeen: false,
                isBookmarked: false,
                dateFound: Date(timeIntervalSince1970: timestamp)
            )

            if savedImages[documentId] == nil {
                savedImages[documentId] = []
            }
            savedImages[documentId]?.append(metadata)
        }

        // Clear pending images after loading
        UserDefaults.standard.removeObject(forKey: key)
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
        if footnotes[footnote.documentId] == nil {
            footnotes[footnote.documentId] = []
        }
        footnotes[footnote.documentId]?.append(footnote)
    }
    
    func getFootnotes(for documentId: UUID) -> [Footnote] {
        return footnotes[documentId] ?? []
    }

    /// Auto-populate footnotes from parsed document packages.
    func populateFootnotes(from packages: CanonicalDocumentPackages, documentId: UUID) {
        let existingFootnotes = footnotes[documentId] ?? []
        let existingIds = Set(existingFootnotes.map { $0.indicator })

        for record in packages.textAnchorsPackage.footnotes {
            guard !existingIds.contains(record.refText) else { continue }

            let footnote = Footnote(
                documentId: documentId,
                indicator: record.refText,
                content: record.bodyText,
                wordIndex: 0,
                contextText: ""
            )
            addFootnote(footnote)
        }
    }

    // MARK: - Curated Items

    @discardableResult
    func addCuratedItem(_ curationItem: CurationItem) -> LibraryItem {
        let coverUrl: URL? = {
            if let urlString = curationItem.content?.coverUrl {
                return URL(string: urlString)
            }
            return nil
        }()
        let sourceUrl: URL? = {
            if let urlString = curationItem.externalUrl ?? curationItem.content?.sourceUrl {
                return URL(string: urlString)
            }
            return nil
        }()

        let item = LibraryItem(
            documentId: UUID(),
            source: .curated(.init(
                contentId: curationItem.contentId ?? curationItem.id,
                sourceUrl: sourceUrl,
                coverUrl: coverUrl,
                fileType: curationItem.content?.fileType ?? curationItem.itemType
            )),
            title: curationItem.displayTitle,
            author: curationItem.displayAuthor,
            wordCount: curationItem.content?.wordCount,
            downloadState: .notDownloaded
        )
        addItem(item)
        return item
    }

    @discardableResult
    func addCuratedItems(_ items: [CurationItem]) -> [LibraryItem] {
        items.map { addCuratedItem($0) }
    }

    // MARK: - Reading Lists

    private static func loadReadingLists() -> [ReadingList] {
        guard let data = UserDefaults.standard.data(forKey: "reading_lists") else {
            return []
        }
        do {
            return try JSONDecoder().decode([ReadingList].self, from: data)
        } catch {
            print("[AppState] Failed to decode reading lists: \(error)")
            return []
        }
    }

    private func saveReadingLists() {
        do {
            let data = try JSONEncoder().encode(readingLists)
            UserDefaults.standard.set(data, forKey: readingListsKey)
        } catch {
            lastError = .persistenceError("Reading lists: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func addReadingList(name: String) -> ReadingList {
        let list = ReadingList(name: name)
        readingLists.append(list)
        return list
    }

    func addItemToList(_ itemId: UUID, listId: UUID) {
        guard let index = readingLists.firstIndex(where: { $0.id == listId }) else { return }
        guard !readingLists[index].itemIds.contains(itemId) else { return }
        readingLists[index].itemIds.append(itemId)
        readingLists[index].updatedAt = Date()
    }

    func removeItemFromList(_ itemId: UUID, listId: UUID) {
        guard let index = readingLists.firstIndex(where: { $0.id == listId }) else { return }
        readingLists[index].itemIds.removeAll { $0 == itemId }
        readingLists[index].updatedAt = Date()
    }

    func updateReadingList(id: UUID, name: String, itemIds: [UUID]) {
        guard let index = readingLists.firstIndex(where: { $0.id == id }) else { return }
        readingLists[index].name = name
        readingLists[index].itemIds = itemIds
        readingLists[index].updatedAt = Date()
    }

    func deleteReadingList(_ listId: UUID) {
        readingLists.removeAll { $0.id == listId }
    }
}
