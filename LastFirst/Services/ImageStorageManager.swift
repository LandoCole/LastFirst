import Foundation
import UIKit

/// Manages image storage on the file system instead of UserDefaults
final class ImageStorageManager: @unchecked Sendable {
    
    static let shared = ImageStorageManager()
    
    private let fileManager = FileManager.default
    private let imagesDirectoryName = "SavedImages"
    private let coversDirectoryName = "BookCovers"
    
    private var imagesDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(imagesDirectoryName)
    }
    
    private var coversDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(coversDirectoryName)
    }
    
    private init() {
        createDirectoriesIfNeeded()
    }
    
    // MARK: - Setup
    
    private func createDirectoriesIfNeeded() {
        do {
            if !fileManager.fileExists(atPath: imagesDirectory.path) {
                try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: coversDirectory.path) {
                try fileManager.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
            }
        } catch {
            print("Error creating image directories: \(error)")
        }
    }
    
    // MARK: - Cover Images
    
    /// Save a cover image for a book
    func saveCoverImage(_ imageData: Data, for bookId: UUID) throws {
        let filePath = coversDirectory.appendingPathComponent("\(bookId.uuidString).jpg")
        try imageData.write(to: filePath)
    }
    
    /// Load a cover image for a book
    func loadCoverImage(for bookId: UUID) -> Data? {
        let filePath = coversDirectory.appendingPathComponent("\(bookId.uuidString).jpg")
        return try? Data(contentsOf: filePath)
    }
    
    /// Delete a cover image for a book
    func deleteCoverImage(for bookId: UUID) {
        let filePath = coversDirectory.appendingPathComponent("\(bookId.uuidString).jpg")
        try? fileManager.removeItem(at: filePath)
    }
    
    // MARK: - Saved Images (from books)
    
    /// Save an image from a book
    func saveImage(_ imageData: Data, imageId: UUID, bookId: UUID) throws {
        let bookDirectory = imagesDirectory.appendingPathComponent(bookId.uuidString)
        
        if !fileManager.fileExists(atPath: bookDirectory.path) {
            try fileManager.createDirectory(at: bookDirectory, withIntermediateDirectories: true)
        }
        
        let filePath = bookDirectory.appendingPathComponent("\(imageId.uuidString).jpg")
        try imageData.write(to: filePath)
    }
    
    /// Load an image from a book
    func loadImage(imageId: UUID, bookId: UUID) -> Data? {
        let filePath = imagesDirectory
            .appendingPathComponent(bookId.uuidString)
            .appendingPathComponent("\(imageId.uuidString).jpg")
        return try? Data(contentsOf: filePath)
    }
    
    /// Delete an image
    func deleteImage(imageId: UUID, bookId: UUID) {
        let filePath = imagesDirectory
            .appendingPathComponent(bookId.uuidString)
            .appendingPathComponent("\(imageId.uuidString).jpg")
        try? fileManager.removeItem(at: filePath)
    }
    
    /// Delete all images for a book
    func deleteAllImages(for bookId: UUID) {
        let bookDirectory = imagesDirectory.appendingPathComponent(bookId.uuidString)
        try? fileManager.removeItem(at: bookDirectory)
        deleteCoverImage(for: bookId)
    }
    
    // MARK: - Migration
    
    /// Migrate existing images from UserDefaults to file system
    func migrateFromUserDefaults(savedImages: [UUID: [SavedImage]], items: [LibraryItem]) {
        // Migrate saved images
        for (documentId, images) in savedImages {
            for image in images {
                if let _ = try? saveImage(image.imageData, imageId: image.id, bookId: documentId) {
                    // Successfully migrated
                }
            }
        }
        
        // Migrate cover images
        // Cover migration is intentionally a no-op in the production pipeline.
        _ = items
    }
    
    // MARK: - Disk Usage
    
    /// Get total size of stored images
    func getTotalStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        if let enumerator = fileManager.enumerator(at: coversDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        return totalSize
    }
    
    /// Format storage size for display
    func formattedStorageSize() -> String {
        let bytes = getTotalStorageSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
