import Foundation
import UIKit
import PDFKit
import Compression
import zlib

struct ParsedDocument {
    var words: [String]
    var chapters: [Chapter]
    var images: [ParsedImage]
    var footnotes: [ParsedFootnote]
    var title: String
    var author: String
    var coverImage: Data?
}

struct ParsedImage {
    var data: Data
    var pageIndex: Int
    var wordIndex: Int
}

struct ParsedFootnote {
    var indicator: String
    var content: String
    var wordIndex: Int
    var contextText: String?
}

class DocumentParser {

    // MARK: - ePub Parsing
    func parseEPub(at path: String) async throws -> ParsedDocument {
        let url = URL(fileURLWithPath: path)

        // ePub is a ZIP file - extract using our ZIP helper
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Extract the ePub ZIP archive
        do {
            try extractZIP(at: url, to: tempDir)
        } catch {
            throw ParserError.parseError("Failed to extract EPUB: \(error.localizedDescription)")
        }

        // Parse container.xml to find the content.opf location
        // Try both with and without META-INF prefix (some EPUBs have different structures)
        var containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        if !FileManager.default.fileExists(atPath: containerPath.path) {
            containerPath = tempDir.appendingPathComponent("meta-inf/container.xml")
        }
        
        guard FileManager.default.fileExists(atPath: containerPath.path) else {
            // List extracted files for debugging
            let contents = try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            throw ParserError.parseError("container.xml not found. Extracted: \(contents ?? [])")
        }

        let containerData = try Data(contentsOf: containerPath)
        let opfPath: URL
        do {
            opfPath = try parseContainerXML(containerData, baseURL: tempDir)
        } catch {
            throw ParserError.parseError("Failed to parse container.xml: \(error)")
        }
        
        guard FileManager.default.fileExists(atPath: opfPath.path) else {
            throw ParserError.parseError("OPF file not found at: \(opfPath.path)")
        }

        // Parse content.opf for metadata and spine
        let opfData = try Data(contentsOf: opfPath)
        let opfInfo: OPFInfo
        do {
            opfInfo = try parseOPF(opfData, baseURL: opfPath.deletingLastPathComponent())
        } catch {
            throw ParserError.parseError("Failed to parse OPF: \(error)")
        }
        
        // If no spine items found, try to find HTML files directly
        var spineItems = opfInfo.spine
        if spineItems.isEmpty {
            let opfDir = opfPath.deletingLastPathComponent()
            if let files = try? FileManager.default.contentsOfDirectory(atPath: opfDir.path) {
                for file in files where file.hasSuffix(".html") || file.hasSuffix(".xhtml") || file.hasSuffix(".htm") {
                    spineItems.append(SpineItem(href: file, title: nil))
                }
            }
        }

        // Parse all HTML/XHTML files in spine order
        var allWords: [String] = []
        var chapters: [Chapter] = []
        var images: [ParsedImage] = []
        var footnotes: [ParsedFootnote] = []

        for (index, spineItem) in spineItems.enumerated() {
            // Handle URL-encoded paths and relative paths
            let decodedHref = spineItem.href.removingPercentEncoding ?? spineItem.href
            var itemPath = opfPath.deletingLastPathComponent().appendingPathComponent(decodedHref)
            
            // Try without path components if not found
            if !FileManager.default.fileExists(atPath: itemPath.path) {
                let filename = URL(fileURLWithPath: decodedHref).lastPathComponent
                itemPath = opfPath.deletingLastPathComponent().appendingPathComponent(filename)
            }

            if FileManager.default.fileExists(atPath: itemPath.path) {
                let htmlData = try Data(contentsOf: itemPath)
                let parseResult = parseHTML(htmlData, startIndex: allWords.count)

                // Create chapter for this spine item
                if !parseResult.words.isEmpty {
                    let chapter = Chapter(
                        title: spineItem.title ?? "Chapter \(index + 1)",
                        startWordIndex: allWords.count,
                        endWordIndex: allWords.count + parseResult.words.count - 1
                    )
                    chapters.append(chapter)
                }

                allWords.append(contentsOf: parseResult.words)

                // Add images with correct word index
                for img in parseResult.images {
                    images.append(ParsedImage(
                        data: img.data,
                        pageIndex: index,
                        wordIndex: img.wordIndex
                    ))
                }
                
                // Add footnotes
                footnotes.append(contentsOf: parseResult.footnotes)
            }
        }
        
        // If still no words, throw an error
        if allWords.isEmpty {
            throw ParserError.parseError("No readable content found in EPUB")
        }

        return ParsedDocument(
            words: allWords,
            chapters: chapters,
            images: images,
            footnotes: footnotes,
            title: opfInfo.title,
            author: opfInfo.author,
            coverImage: opfInfo.coverImage
        )
    }

    // MARK: - PDF Parsing
    func parsePDF(at path: String) async throws -> ParsedDocument {
        let url = URL(fileURLWithPath: path)
        guard let document = PDFDocument(url: url) else {
            throw ParserError.invalidFile
        }

        var allWords: [String] = []
        let images: [ParsedImage] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            // Extract text
            if let pageText = page.string {
                let words = pageText.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }

                allWords.append(contentsOf: words)
            }

            // Extract images (simplified - full implementation would use CGPDFScanner)
            // This is a placeholder for image extraction
        }

        // Create chapters based on page count (simplified)
        var chapters: [Chapter] = []
        let wordsPerPage = allWords.count / max(1, document.pageCount)
        for pageIndex in 0..<min(10, document.pageCount) {
            let startIndex = pageIndex * wordsPerPage
            let endIndex = min((pageIndex + 1) * wordsPerPage - 1, allWords.count - 1)
            if startIndex < endIndex {
                chapters.append(Chapter(
                    title: "Page \(pageIndex + 1)",
                    startWordIndex: startIndex,
                    endWordIndex: endIndex
                ))
            }
        }

        return ParsedDocument(
            words: allWords,
            chapters: chapters,
            images: images,
            footnotes: [],
            title: url.deletingPathExtension().lastPathComponent,
            author: "Unknown",
            coverImage: nil
        )
    }

    // MARK: - Plain Text Parsing
    func parseText(at path: String) async throws -> ParsedDocument {
        let url = URL(fileURLWithPath: path)
        let text = try String(contentsOf: url, encoding: .utf8)

        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        // Create chapters based on paragraph breaks (double newlines)
        let paragraphs = text.components(separatedBy: "\n\n")
        var chapters: [Chapter] = []
        var currentWordIndex = 0

        for (index, paragraph) in paragraphs.enumerated() {
            let paragraphWords = paragraph.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }

            if !paragraphWords.isEmpty {
                chapters.append(Chapter(
                    title: "Section \(index + 1)",
                    startWordIndex: currentWordIndex,
                    endWordIndex: currentWordIndex + paragraphWords.count - 1
                ))
                currentWordIndex += paragraphWords.count
            }
        }

        return ParsedDocument(
            words: words,
            chapters: chapters,
            images: [],
            footnotes: [],
            title: url.deletingPathExtension().lastPathComponent,
            author: "Unknown",
            coverImage: nil
        )
    }

    // MARK: - ZIP Extraction (Basic Implementation)
    // Note: For production, consider using ZIPFoundation for better reliability
    private func extractZIP(at source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let data = try Data(contentsOf: source)

        // Helper to read unaligned little-endian values safely
        func readUInt16(at position: Int) -> UInt16 {
            guard position + 2 <= data.count else { return 0 }
            return UInt16(data[position]) | (UInt16(data[position + 1]) << 8)
        }
        
        func readUInt32(at position: Int) -> UInt32 {
            guard position + 4 <= data.count else { return 0 }
            return UInt32(data[position]) |
                   (UInt32(data[position + 1]) << 8) |
                   (UInt32(data[position + 2]) << 16) |
                   (UInt32(data[position + 3]) << 24)
        }

        // Basic ZIP parsing - find local file headers
        var offset = 0
        while offset < data.count - 4 {
            // Look for local file header signature (0x04034b50)
            let sig = readUInt32(at: offset)

            if sig == 0x04034b50 {
                // Parse local file header
                let compressionMethod = readUInt16(at: offset + 8)
                let compressedSize = readUInt32(at: offset + 18)
                let uncompressedSize = readUInt32(at: offset + 22)
                let fileNameLength = readUInt16(at: offset + 26)
                let extraFieldLength = readUInt16(at: offset + 28)

                let fileNameStart = offset + 30
                let fileNameEnd = fileNameStart + Int(fileNameLength)
                
                guard fileNameEnd <= data.count else { break }
                let fileName = String(data: data[fileNameStart..<fileNameEnd], encoding: .utf8) ?? ""

                let dataStart = fileNameEnd + Int(extraFieldLength)
                let dataEnd = dataStart + Int(compressedSize)
                
                guard dataEnd <= data.count else { break }

                if !fileName.isEmpty && !fileName.hasSuffix("/") {
                    let filePath = destination.appendingPathComponent(fileName)

                    // Create directory if needed
                    try fileManager.createDirectory(
                        at: filePath.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    // Extract file data
                    if compressionMethod == 0 {
                        // Stored (no compression)
                        let fileData = data[dataStart..<dataEnd]
                        try fileData.write(to: filePath)
                    } else if compressionMethod == 8 {
                        // Deflate compression
                        let compressedData = Data(data[dataStart..<dataEnd])
                        if let decompressed = decompressDeflate(compressedData, expectedSize: Int(uncompressedSize)) {
                            try decompressed.write(to: filePath)
                        }
                    }
                }

                offset = dataEnd
            } else {
                offset += 1
            }
        }
    }

    private func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0, !data.isEmpty else { return Data() }
        
        // Use zlib's inflateInit2 with negative windowBits for raw deflate
        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil
        
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destinationBuffer.deallocate() }
        
        // -15 windowBits = raw deflate (no zlib/gzip header)
        let initResult = data.withUnsafeBytes { srcPtr -> Int32 in
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = UInt32(data.count)
            stream.next_out = destinationBuffer
            stream.avail_out = UInt32(expectedSize)
            return inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        
        guard initResult == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        
        let inflateResult = inflate(&stream, Z_FINISH)
        
        if inflateResult == Z_STREAM_END || inflateResult == Z_OK {
            let outputSize = expectedSize - Int(stream.avail_out)
            if outputSize > 0 {
                return Data(bytes: destinationBuffer, count: outputSize)
            }
        }
        
        return nil
    }

    private func parseContainerXML(_ data: Data, baseURL: URL) throws -> URL {
        // Simple XML parsing to find rootfile path
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw ParserError.invalidFile
        }

        // Find full-path attribute in rootfile element
        if let range = xmlString.range(of: "full-path=\""),
           let endRange = xmlString[range.upperBound...].range(of: "\"") {
            let path = String(xmlString[range.upperBound..<endRange.lowerBound])
            return baseURL.appendingPathComponent(path)
        }

        throw ParserError.invalidFile
    }

    struct OPFInfo {
        var title: String
        var author: String
        var coverImage: Data?
        var spine: [SpineItem]
    }

    struct SpineItem {
        var href: String
        var title: String?
    }

    private func parseOPF(_ data: Data, baseURL: URL) throws -> OPFInfo {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw ParserError.invalidFile
        }

        // Extract title
        var title = "Unknown Title"
        if let titleRange = xmlString.range(of: "<dc:title>"),
           let titleEndRange = xmlString[titleRange.upperBound...].range(of: "</dc:title>") {
            title = String(xmlString[titleRange.upperBound..<titleEndRange.lowerBound])
        }

        // Extract author
        var author = "Unknown Author"
        if let authorRange = xmlString.range(of: "<dc:creator"),
           let authorStartRange = xmlString[authorRange.upperBound...].range(of: ">"),
           let authorEndRange = xmlString[authorStartRange.upperBound...].range(of: "</dc:creator>") {
            author = String(xmlString[authorStartRange.upperBound..<authorEndRange.lowerBound])
        }

        // Build manifest dictionary (id -> href)
        var manifest: [String: String] = [:]
        let itemPattern = #"<item\s+[^>]*id="([^"]+)"[^>]*href="([^"]+)"[^>]*/?\s*>"#
        let itemPatternAlt = #"<item\s+[^>]*href="([^"]+)"[^>]*id="([^"]+)"[^>]*/?\s*>"#
        
        if let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: []) {
            let matches = itemRegex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: xmlString),
                   let hrefRange = Range(match.range(at: 2), in: xmlString) {
                    let id = String(xmlString[idRange])
                    let href = String(xmlString[hrefRange])
                    manifest[id] = href
                }
            }
        }
        
        // Try alternate pattern (href before id)
        if let itemRegex = try? NSRegularExpression(pattern: itemPatternAlt, options: []) {
            let matches = itemRegex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
            for match in matches {
                if let hrefRange = Range(match.range(at: 1), in: xmlString),
                   let idRange = Range(match.range(at: 2), in: xmlString) {
                    let id = String(xmlString[idRange])
                    let href = String(xmlString[hrefRange])
                    if manifest[id] == nil {
                        manifest[id] = href
                    }
                }
            }
        }

        // Extract spine items (ordered list of content)
        var spineItems: [SpineItem] = []
        let spinePattern = #"<itemref\s+[^>]*idref="([^"]+)"[^>]*/?\s*>"#
        
        if let spineRegex = try? NSRegularExpression(pattern: spinePattern, options: []) {
            let matches = spineRegex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
            for match in matches {
                if let idrefRange = Range(match.range(at: 1), in: xmlString) {
                    let idref = String(xmlString[idrefRange])
                    if let href = manifest[idref] {
                        // Only include HTML/XHTML files
                        if href.hasSuffix(".html") || href.hasSuffix(".xhtml") || href.hasSuffix(".htm") {
                            spineItems.append(SpineItem(href: href, title: nil))
                        }
                    }
                }
            }
        }
        
        // Try to extract cover image
        var coverImage: Data? = nil
        let coverPattern = #"<meta\s+[^>]*name="cover"[^>]*content="([^"]+)"[^>]*/?\s*>"#
        if let coverRegex = try? NSRegularExpression(pattern: coverPattern, options: []),
           let match = coverRegex.firstMatch(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString)),
           let coverIdRange = Range(match.range(at: 1), in: xmlString) {
            let coverId = String(xmlString[coverIdRange])
            if let coverHref = manifest[coverId] {
                let coverPath = baseURL.appendingPathComponent(coverHref)
                coverImage = try? Data(contentsOf: coverPath)
            }
        }

        return OPFInfo(
            title: title,
            author: author,
            coverImage: coverImage,
            spine: spineItems
        )
    }

    private func parseHTML(_ data: Data, startIndex: Int) -> (words: [String], images: [ParsedImage], footnotes: [ParsedFootnote]) {
        guard let htmlString = String(data: data, encoding: .utf8) else {
            return ([], [], [])
        }
        
        var footnotes: [ParsedFootnote] = []
        
        // Extract footnotes before stripping HTML
        // Look for common footnote patterns: [1], [2], superscript numbers, etc.
        let footnotePatterns = [
            // Pattern for footnote references like [1], [2], etc.
            #"\[(\d+)\]"#,
            // Pattern for superscript-style footnotes
            #"<sup[^>]*>(\d+)</sup>"#,
            // Pattern for footnote anchors
            #"<a[^>]*class="[^"]*footnote[^"]*"[^>]*>([^<]+)</a>"#
        ]
        
        // Try to find footnote content sections
        let footnoteContentPattern = #"<div[^>]*class="[^"]*footnote[^"]*"[^>]*>([\s\S]*?)</div>"#
        if let regex = try? NSRegularExpression(pattern: footnoteContentPattern, options: []) {
            let matches = regex.matches(in: htmlString, options: [], range: NSRange(htmlString.startIndex..., in: htmlString))
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: htmlString) {
                    var content = String(htmlString[contentRange])
                    // Strip HTML from content
                    content = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    content = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !content.isEmpty {
                        // Try to extract indicator from content
                        let indicator = extractFootnoteIndicator(from: content) ?? "•"
                        footnotes.append(ParsedFootnote(
                            indicator: indicator,
                            content: content,
                            wordIndex: startIndex,
                            contextText: nil
                        ))
                    }
                }
            }
        }

        // Strip HTML tags (simplified)
        var text = htmlString

        // Remove script and style content
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Remove all HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")

        // Split into words
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        return (words, [], footnotes)
    }
    
    private func extractFootnoteIndicator(from text: String) -> String? {
        // Try to extract a number or symbol at the start
        let patterns = [
            #"^(\d+)[.\):\s]"#,
            #"^\[(\d+)\]"#,
            #"^([*†‡§])"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    enum ParserError: Error {
        case invalidFile
        case notImplemented
        case parseError(String)
    }
}
