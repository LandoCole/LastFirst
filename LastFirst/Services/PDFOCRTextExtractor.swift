import Foundation
import PDFKit
import Vision
import UIKit

final class PDFOCRTextExtractor {
    enum ExtractionError: Error {
        case invalidPDF
        case couldNotRenderPage
    }

    private struct CacheEntry: Codable {
        var pageTexts: [String]
        var createdAt: Date
        var fileSize: Int64
        var fileModificationTime: TimeInterval
    }

    private let cacheFolderName = "pdf_ocr_cache_v1"

    func extractTextByPage(from url: URL) async throws -> [String] {
        let (fileSize, modTime) = try fileFingerprint(for: url)

        if let cached = try loadCache(for: url, fileSize: fileSize, modTime: modTime) {
            return cached
        }

        guard let pdf = PDFDocument(url: url) else {
            throw ExtractionError.invalidPDF
        }

        var pageTexts: [String] = []
        pageTexts.reserveCapacity(pdf.pageCount)

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else {
                pageTexts.append("")
                continue
            }

            // Try native text layer first (much faster than OCR)
            if let nativeText = page.string,
               nativeText.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                pageTexts.append(nativeText)
                continue
            }

            // Fall back to OCR for scanned/image-only pages
            let text = try await ocrText(for: page)
            pageTexts.append(text)
        }

        try saveCache(pageTexts, for: url, fileSize: fileSize, modTime: modTime)
        return pageTexts
    }

    private func ocrText(for page: PDFPage) async throws -> String {
        let maxDimension: CGFloat = 2200
        let image = page.thumbnail(of: CGSize(width: maxDimension, height: maxDimension), for: .mediaBox)
        guard let cgImage = image.cgImage else {
            throw ExtractionError.couldNotRenderPage
        }

        let strings = try await recognizeStrings(in: cgImage)
        return strings.joined(separator: " ")
    }

    private func recognizeStrings(in cgImage: CGImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
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
