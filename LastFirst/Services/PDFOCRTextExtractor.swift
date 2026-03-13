import Foundation
import PDFKit
import Vision
import UIKit

final class PDFOCRTextExtractor {
    enum ExtractionError: Error, LocalizedError {
        case invalidPDF
        case couldNotRenderPage
        case passwordProtected
        case ocrTimeout

        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "The PDF file could not be opened."
            case .couldNotRenderPage: return "A page in the PDF could not be rendered."
            case .passwordProtected: return "This PDF is password-protected."
            case .ocrTimeout: return "OCR processing timed out on a page."
            }
        }
    }

    private struct CacheEntry: Codable {
        var pageTexts: [String]
        var createdAt: Date
        var fileSize: Int64
        var fileModificationTime: TimeInterval
    }

    private let cacheFolderName = "pdf_ocr_cache_v1"
    private let ocrTimeoutSeconds: UInt64 = 30
    private let batchSize = 20

    func extractTextByPage(from url: URL) async throws -> [String] {
        let (fileSize, modTime) = try fileFingerprint(for: url)

        if let cached = try loadCache(for: url, fileSize: fileSize, modTime: modTime) {
            return cached
        }

        guard let pdf = PDFDocument(url: url) else {
            throw ExtractionError.invalidPDF
        }

        // Detect encrypted/locked PDFs
        if pdf.isEncrypted && pdf.isLocked {
            throw ExtractionError.passwordProtected
        }

        var pageTexts: [String] = []
        pageTexts.reserveCapacity(pdf.pageCount)

        // Large PDF batching: process in groups to manage memory
        let totalPages = pdf.pageCount
        let useBatching = totalPages > 200

        if useBatching {
            for batchStart in stride(from: 0, to: totalPages, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, totalPages)
                let batchTexts = await extractBatch(pdf: pdf, from: batchStart, to: batchEnd)
                pageTexts.append(contentsOf: batchTexts)
            }
        } else {
            for pageIndex in 0..<totalPages {
                let text = await extractSinglePage(pdf: pdf, pageIndex: pageIndex)
                pageTexts.append(text)
            }
        }

        try saveCache(pageTexts, for: url, fileSize: fileSize, modTime: modTime)
        return pageTexts
    }

    /// Extracts text for a batch of pages, yielding between batches to manage memory.
    private func extractBatch(pdf: PDFDocument, from startIndex: Int, to endIndex: Int) async -> [String] {
        var texts: [String] = []
        texts.reserveCapacity(endIndex - startIndex)

        for pageIndex in startIndex..<endIndex {
            let text = await extractSinglePage(pdf: pdf, pageIndex: pageIndex)
            texts.append(text)
        }
        // Yield to allow memory cleanup between batches
        await Task.yield()
        return texts
    }

    /// Extracts text from a single page with error isolation — one bad page doesn't fail the whole doc.
    private func extractSinglePage(pdf: PDFDocument, pageIndex: Int) async -> String {
        guard let page = pdf.page(at: pageIndex) else {
            return ""
        }

        // Try native text layer first (much faster than OCR)
        // Lowered threshold from 20 to 5 chars to reduce unnecessary OCR
        if let nativeText = page.string,
           nativeText.trimmingCharacters(in: .whitespacesAndNewlines).count > 5 {
            return nativeText
        }

        // Fall back to OCR with timeout and error isolation
        do {
            return try await ocrTextWithTimeout(for: page)
        } catch {
            print("[PDFOCRTextExtractor] OCR failed for page \(pageIndex + 1): \(error)")
            // Return native text even if short, or empty string
            return page.string ?? ""
        }
    }

    private func ocrTextWithTimeout(for page: PDFPage) async throws -> String {
        // Render the image on the current context before entering the task group,
        // since PDFPage is not Sendable.
        let maxDimension: CGFloat = 2200
        let image = page.thumbnail(of: CGSize(width: maxDimension, height: maxDimension), for: .mediaBox)
        guard let cgImage = image.cgImage else {
            throw ExtractionError.couldNotRenderPage
        }

        let timeoutNanos = ocrTimeoutSeconds * 1_000_000_000
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [cgImage] in
                let strings = try await PDFOCRTextExtractor.recognizeStrings(in: cgImage)
                return strings.joined(separator: " ")
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw ExtractionError.ocrTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func recognizeStrings(in cgImage: CGImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try requestHandler.perform([request])

            let observations: [VNRecognizedTextObservation] = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    private func fileFingerprint(for url: URL) throws -> (Int64, TimeInterval) {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values.fileSize ?? 0)
        let modTime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return (size, modTime)
    }

    private func cacheDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(cacheFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cacheKey(for url: URL, fileSize: Int64, modTime: TimeInterval) -> String {
        let safeName = url.lastPathComponent.replacingOccurrences(of: "/", with: "_")
        return "\(safeName)_\(fileSize)_\(Int64(modTime))"
    }

    private func cacheFileURL(for url: URL, fileSize: Int64, modTime: TimeInterval) throws -> URL {
        let dir = try cacheDirectory()
        return dir.appendingPathComponent(cacheKey(for: url, fileSize: fileSize, modTime: modTime)).appendingPathExtension("json")
    }

    private func loadCache(for url: URL, fileSize: Int64, modTime: TimeInterval) throws -> [String]? {
        let cacheURL = try cacheFileURL(for: url, fileSize: fileSize, modTime: modTime)
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }

        let data = try Data(contentsOf: cacheURL)
        let entry = try JSONDecoder().decode(CacheEntry.self, from: data)

        if entry.fileSize != fileSize || entry.fileModificationTime != modTime {
            return nil
        }

        return entry.pageTexts
    }

    private func saveCache(_ pageTexts: [String], for url: URL, fileSize: Int64, modTime: TimeInterval) throws {
        let cacheURL = try cacheFileURL(for: url, fileSize: fileSize, modTime: modTime)
        let entry = CacheEntry(pageTexts: pageTexts, createdAt: Date(), fileSize: fileSize, fileModificationTime: modTime)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: cacheURL, options: [.atomic])
    }
}
