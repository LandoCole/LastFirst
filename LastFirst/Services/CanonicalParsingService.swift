import Foundation
import UIKit
import PDFKit
import EPUBKit
import Readability

actor CanonicalParsingService {
    static let shared = CanonicalParsingService()

    enum ParsingError: Error, LocalizedError {
        case unsupportedSource
        case invalidEPUB
        case emptyContent
        case fileNotFound
        case corruptPDF
        case passwordProtectedPDF

        var errorDescription: String? {
            switch self {
            case .unsupportedSource: return "This file type is not supported."
            case .invalidEPUB: return "This EPUB file could not be opened."
            case .emptyContent: return "This document appears to be empty."
            case .fileNotFound: return "The file could not be found."
            case .corruptPDF: return "This PDF file appears to be damaged and cannot be read."
            case .passwordProtectedPDF: return "This PDF is password-protected. Please unlock it before importing."
            }
        }
    }

    private enum Versions {
        static let parser = 2
        static let normalizer = 1
        static let segmenter = 1
    }

    private enum ImageConstants {
        static let coverMaxDimension: CGFloat = 400
        static let articleImageMaxDimension: CGFloat = 800
        static let jpegQuality: CGFloat = 0.8
    }

    private let resourceCache: ResourceCacheActor
    private let documentStore: DocumentStoreActor
    private let imageStorage = ImageStorageManager.shared
    private var isCoordinatorConfigured = false

    init(
        resourceCache: ResourceCacheActor = .shared,
        documentStore: DocumentStoreActor = .shared
    ) {
        self.resourceCache = resourceCache
        self.documentStore = documentStore
    }

    func configureCoordinatorIfNeeded() async {
        guard !isCoordinatorConfigured else { return }
        isCoordinatorConfigured = true

        await ParsingCoordinatorActor.shared.setHandler { request in
            let packages = try await self.parse(request: request)
            try await self.documentStore.save(packages)
            return packages
        }
    }

    func parse(request: ParsingCoordinatorActor.ParseRequest) async throws -> CanonicalDocumentPackages {
        switch request.source {
        case .localFile(let local):
            switch local.fileType {
            case .epub:
                return try await parseEPUB(documentId: request.documentId, url: local.url)
            case .pdf:
                return try await parsePDF(documentId: request.documentId, url: local.url)
            }
        case .web(let web):
            return try await parseWeb(documentId: request.documentId, url: web.url)
        }
    }

    private func parseEPUB(documentId: UUID, url: URL) async throws -> CanonicalDocumentPackages {
        guard let epub = EPUBDocument(url: url) else {
            throw ParsingError.invalidEPUB
        }

        // Extract and save cover image
        extractAndSaveEPUBCover(epub: epub, documentId: documentId)

        // Extract and save document images for artifacts
        extractAndSaveEPUBImages(epub: epub, documentId: documentId)

        for item in epub.manifest.items.values {
            let sourceURL = epub.contentDirectory.appendingPathComponent(item.path)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            _ = try await resourceCache.storeFile(at: sourceURL, documentId: documentId, relativePath: item.path)
        }

        let tocTitles = tocTitleByPath(from: epub.tableOfContents)
        var renderUnits: [RenderUnit] = []
        var readingUnits: [ReadingUnit] = []
        var unitStructuralElements: [[StructuralElement]] = []

        let structuralParser = EPUBStructuralParser()

        for (index, spineItem) in epub.spine.items.enumerated() {
            guard let manifestItem = epub.manifest.items[spineItem.idref] else { continue }
            let normalizedPath = normalizePath(manifestItem.path)
            let title = tocTitles[normalizedPath] ?? "Section \(index + 1)"
            let unitID = spineItem.idref

            renderUnits.append(RenderUnit(unitID: unitID, entryPath: manifestItem.path, title: title))
            readingUnits.append(ReadingUnit(id: unitID, title: title, kind: .chapter, order: index))

            let htmlURL = epub.contentDirectory.appendingPathComponent(manifestItem.path)
            let elements = structuralParser.parse(xhtmlURL: htmlURL)
            unitStructuralElements.append(elements)
        }

        guard !renderUnits.isEmpty else {
            throw ParsingError.emptyContent
        }

        // Extract metadata from OPF and navigation document
        let metadataExtractor = EPUBMetadataExtractor()
        var extractedPageList: [PageListEntry] = []

        // Try to find nav document in manifest
        let manifestItems = Array(epub.manifest.items.values)
        if let navItem = manifestItems.first(where: { $0.property?.contains("nav") == true }) ??
           manifestItems.first(where: { $0.mediaType == .xHTML && $0.id.lowercased().contains("nav") }) {
            let navURL = epub.contentDirectory.appendingPathComponent(navItem.path)
            let (pageList, _) = metadataExtractor.extractFromNavDocument(at: navURL)
            extractedPageList = pageList
        }

        let textAnchors = buildStructuralTextAnchorsPackage(
            units: readingUnits,
            unitElements: unitStructuralElements,
            pageList: extractedPageList,
            parserVersion: Versions.parser,
            normalizerVersion: Versions.normalizer,
            segmenterVersion: Versions.segmenter
        )

        let manifest = DocumentManifest(
            id: documentId,
            title: epub.title ?? "Untitled",
            authors: [epub.author].compactMap { $0 },
            languageCode: epub.metadata.language,
            identifiers: [epub.metadata.identifier].compactMap { id in
                id.map { DocumentIdentifier(scheme: "epub", value: $0) }
            },
            documentType: .epub,
            parserVersion: Versions.parser,
            normalizerVersion: Versions.normalizer,
            segmenterVersion: Versions.segmenter
        )

        let renderPackage = RenderPackage(
            format: .html,
            baseURL: offlineBaseURL(for: documentId),
            units: renderUnits
        )

        return CanonicalDocumentPackages(
            manifest: manifest,
            renderPackage: renderPackage,
            textAnchorsPackage: textAnchors
        )
    }

    private func parsePDF(documentId: UUID, url: URL) async throws -> CanonicalDocumentPackages {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParsingError.fileNotFound
        }

        guard let document = PDFDocument(url: url) else {
            throw ParsingError.corruptPDF
        }

        if document.isEncrypted && document.isLocked {
            throw ParsingError.passwordProtectedPDF
        }

        // Extract and save first page as cover
        extractAndSavePDFCover(document: document, documentId: documentId)

        let extractor = PDFOCRTextExtractor()
        let pageTexts: [String]
        do {
            pageTexts = try await extractor.extractTextByPage(from: url)
        } catch {
            // Fallback: try native-text-only extraction if OCR fails
            print("[CanonicalParsingService] OCR extraction failed, attempting native text only: \(error)")
            var fallbackTexts: [String] = []
            for i in 0..<document.pageCount {
                fallbackTexts.append(document.page(at: i)?.string ?? "")
            }
            pageTexts = fallbackTexts
        }
        let title = url.deletingPathExtension().lastPathComponent

        let renderPath = "document.pdf"
        _ = try await resourceCache.storeFile(at: url, documentId: documentId, relativePath: renderPath)

        let units = (0..<document.pageCount).map { index in
            ReadingUnit(id: "page-\(index + 1)", title: "Page \(index + 1)", kind: .document, order: index)
        }

        let unitTexts = (0..<document.pageCount).map { index in
            index < pageTexts.count ? pageTexts[index] : ""
        }

        let textAnchors = buildTextAnchorsPackage(
            units: units,
            unitTexts: unitTexts,
            segmentKind: .page,
            parserVersion: Versions.parser,
            normalizerVersion: Versions.normalizer,
            segmenterVersion: Versions.segmenter
        )

        let manifest = DocumentManifest(
            id: documentId,
            title: title.isEmpty ? "Untitled" : title,
            authors: [],
            languageCode: nil,
            identifiers: [DocumentIdentifier(scheme: "file", value: url.lastPathComponent)],
            documentType: .pdf,
            parserVersion: Versions.parser,
            normalizerVersion: Versions.normalizer,
            segmenterVersion: Versions.segmenter
        )

        let renderPackage = RenderPackage(
            format: .pdf,
            baseURL: offlineBaseURL(for: documentId),
            units: [RenderUnit(unitID: "pdf", entryPath: renderPath, title: title)]
        )

        return CanonicalDocumentPackages(
            manifest: manifest,
            renderPackage: renderPackage,
            textAnchorsPackage: textAnchors
        )
    }

    private func parseWeb(documentId: UUID, url: URL) async throws -> CanonicalDocumentPackages {
        // Try Firecrawl first (handles JS-rendered sites), fall back to Readability
        let (title, htmlContent, textContent, byline, siteName, language) = try await extractWebContent(url: url)

        // Extract and save cover image (first image) and article images
        await extractAndSaveWebImages(htmlContent: htmlContent, baseURL: url, documentId: documentId)

        let html = wrapHTMLDocument(title: title, bodyHTML: htmlContent)
        let htmlData = Data(html.utf8)
        let entryPath = "index.html"

        _ = try await resourceCache.store(data: htmlData, documentId: documentId, relativePath: entryPath)

        let unit = ReadingUnit(id: "article", title: title, kind: .article, order: 0)
        let textAnchors = buildTextAnchorsPackage(
            units: [unit],
            unitTexts: [textContent],
            segmentKind: .paragraphGroup,
            parserVersion: Versions.parser,
            normalizerVersion: Versions.normalizer,
            segmenterVersion: Versions.segmenter
        )

        let manifest = DocumentManifest(
            id: documentId,
            title: title.isEmpty ? (siteName ?? "Untitled") : title,
            authors: [byline].compactMap { $0 },
            languageCode: language,
            identifiers: [DocumentIdentifier(scheme: "url", value: url.absoluteString)],
            documentType: .web,
            parserVersion: Versions.parser,
            normalizerVersion: Versions.normalizer,
            segmenterVersion: Versions.segmenter
        )

        let renderPackage = RenderPackage(
            format: .html,
            baseURL: offlineBaseURL(for: documentId),
            units: [RenderUnit(unitID: "article", entryPath: entryPath, title: title)]
        )

        return CanonicalDocumentPackages(
            manifest: manifest,
            renderPackage: renderPackage,
            textAnchorsPackage: textAnchors
        )
    }

    /// Extracts web content via Firecrawl Edge Function, falling back to Readability for offline use.
    private func extractWebContent(url: URL) async throws -> (title: String, content: String, textContent: String, byline: String?, siteName: String?, language: String?) {
        // Try Firecrawl (server-side, handles JS-rendered pages)
        do {
            let result = try await SupabaseManager.shared.scrapeURL(url: url)
            let htmlContent = result.content.isEmpty ? markdownToBasicHTML(result.markdown) : result.content
            let text = result.textContent.isEmpty ? result.markdown : result.textContent
            return (result.title, htmlContent, text, result.byline, result.siteName, result.language)
        } catch {
            print("[CanonicalParsingService] Firecrawl failed, falling back to Readability: \(error)")
        }

        // Fallback: Readability (client-side, static HTML only)
        let result = try await parseReadability(url: url)
        return (result.title, result.content, result.textContent, result.byline, result.siteName, result.language)
    }

    /// Converts markdown to basic HTML for rendering.
    private func markdownToBasicHTML(_ markdown: String) -> String {
        var html = markdown
        // Headings
        html = html.replacingOccurrences(of: #"(?m)^### (.+)$"#, with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^## (.+)$"#, with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^# (.+)$"#, with: "<h1>$1</h1>", options: .regularExpression)
        // Bold and italic
        html = html.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        // Paragraphs (double newline)
        let paragraphs = html.components(separatedBy: "\n\n")
        html = paragraphs.map { para in
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            if trimmed.hasPrefix("<h") { return trimmed }
            return "<p>\(trimmed)</p>"
        }.joined(separator: "\n")
        return html
    }

    @MainActor
    private func parseReadability(url: URL) async throws -> ReadabilityResult {
        try await Readability().parse(url: url)
    }

    private func offlineBaseURL(for documentId: UUID) -> URL {
        URL(string: "reader-resource://\(documentId.uuidString)/") ?? urlFallbackBaseURL(for: documentId)
    }

    private func urlFallbackBaseURL(for documentId: UUID) -> URL {
        URL(string: "reader-resource://\(documentId.uuidString)/")!
    }

    private func wrapHTMLDocument(title: String, bodyHTML: String) -> String {
        let escapedTitle = title.isEmpty ? "Untitled" : title
        return """
        <!doctype html>
        <html>
          <head>
            <meta charset=\"utf-8\" />
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\" />
            <title>\(escapedTitle)</title>
          </head>
          <body>\(bodyHTML)</body>
        </html>
        """
    }

    private func plainText(fromHTMLAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return plainText(fromHTMLData: data)
    }

    private func plainText(fromHTMLData data: Data) -> String {
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }

        let raw = String(decoding: data, as: UTF8.self)
        return raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private func buildTextAnchorsPackage(
        units: [ReadingUnit],
        unitTexts: [String],
        segmentKind: ContentSegmentKind,
        parserVersion: Int,
        normalizerVersion: Int,
        segmenterVersion: Int
    ) -> TextAnchorsPackage {
        var segments: [ContentSegment] = []
        var anchors: [AnchorRecord] = []

        var plainText = ""
        for (index, unit) in units.enumerated() {
            let text = index < unitTexts.count ? unitTexts[index] : ""
            let segmentID = "segment-\(index)"
            let anchorID = "anchor-\(index)"
            let start = plainText.count

            plainText += text
            let end = plainText.count

            segments.append(ContentSegment(
                id: segmentID,
                unitID: unit.id,
                anchorID: anchorID,
                kind: segmentKind,
                order: index,
                text: text,
                textRange: TextRange(start: start, end: end)
            ))

            let progress = units.isEmpty ? 0 : Double(index) / Double(max(units.count - 1, 1))
            anchors.append(AnchorRecord(id: anchorID, unitID: unit.id, progress: progress, segmentID: segmentID))

            if index < units.count - 1 {
                plainText += "\n\n"
            }
        }

        return TextAnchorsPackage(
            plainText: plainText,
            units: units,
            segments: segments,
            anchors: anchors,
            parserVersion: parserVersion,
            normalizerVersion: normalizerVersion,
            segmenterVersion: segmenterVersion
        )
    }

    private func buildStructuralTextAnchorsPackage(
        units: [ReadingUnit],
        unitElements: [[StructuralElement]],
        pageList: [PageListEntry],
        parserVersion: Int,
        normalizerVersion: Int,
        segmenterVersion: Int
    ) -> TextAnchorsPackage {
        var segments: [ContentSegment] = []
        var anchors: [AnchorRecord] = []
        var footnoteRefs: [String: (refText: String, unitID: String)] = [:]
        var footnoteBodies: [String: (bodyText: String, unitID: String)] = [:]
        var plainText = ""
        var segmentOrder = 0

        for (unitIndex, unit) in units.enumerated() {
            let elements = unitIndex < unitElements.count ? unitElements[unitIndex] : []
            let anchorID = "anchor-\(unitIndex)"
            let progress = units.isEmpty ? 0 : Double(unitIndex) / Double(max(units.count - 1, 1))
            anchors.append(AnchorRecord(id: anchorID, unitID: unit.id, progress: progress, segmentID: nil))

            for element in elements {
                let structuralKind: StructuralContentKind?
                let segmentKind: ContentSegmentKind

                switch element.kind {
                case .heading(let level):
                    segmentKind = .headingGroup
                    switch level {
                    case 1: structuralKind = .heading1
                    case 2: structuralKind = .heading2
                    case 3: structuralKind = .heading3
                    case 4: structuralKind = .heading4
                    case 5: structuralKind = .heading5
                    default: structuralKind = .heading6
                    }
                case .paragraph:
                    segmentKind = .paragraphGroup
                    structuralKind = .paragraph
                case .listItem:
                    segmentKind = .paragraphGroup
                    structuralKind = .listItem
                case .blockquote:
                    segmentKind = .paragraphGroup
                    structuralKind = .blockquote
                case .codeBlock:
                    segmentKind = .paragraphGroup
                    structuralKind = .codeBlock
                case .image:
                    segmentKind = .paragraphGroup
                    structuralKind = .image
                case .divider:
                    segmentKind = .paragraphGroup
                    structuralKind = .divider
                case .footnoteRef(let targetId, let displayText):
                    footnoteRefs[targetId] = (refText: displayText, unitID: unit.id)
                    continue
                case .footnoteBody(let id):
                    footnoteBodies[id] = (bodyText: element.text, unitID: unit.id)
                    continue
                }

                let text = element.text
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let segmentID = "segment-\(segmentOrder)"
                let start = plainText.count
                plainText += text
                let end = plainText.count

                segments.append(ContentSegment(
                    id: segmentID,
                    unitID: unit.id,
                    anchorID: anchorID,
                    kind: segmentKind,
                    order: segmentOrder,
                    text: text,
                    textRange: TextRange(start: start, end: end),
                    structuralKind: structuralKind
                ))

                // Update anchor to point to first segment
                if anchors[unitIndex].segmentID == nil {
                    anchors[unitIndex].segmentID = segmentID
                }

                segmentOrder += 1
                plainText += "\n\n"
            }
        }

        // Build footnote records by matching refs to bodies
        var footnotes: [FootnoteRecord] = []
        for (targetId, ref) in footnoteRefs {
            if let body = footnoteBodies[targetId] {
                footnotes.append(FootnoteRecord(
                    id: targetId,
                    refText: ref.refText,
                    bodyText: body.bodyText,
                    unitID: ref.unitID
                ))
            }
        }

        return TextAnchorsPackage(
            plainText: plainText,
            units: units,
            segments: segments,
            anchors: anchors,
            footnotes: footnotes,
            pageList: pageList,
            parserVersion: parserVersion,
            normalizerVersion: normalizerVersion,
            segmenterVersion: segmenterVersion
        )
    }

    private func tocTitleByPath(from toc: EPUBTableOfContents) -> [String: String] {
        var titles: [String: String] = [:]

        func walk(_ node: EPUBTableOfContents) {
            if let item = node.item {
                let path = normalizePath(item)
                if titles[path] == nil {
                    titles[path] = node.label
                }
            }
            node.subTable?.forEach { walk($0) }
        }

        walk(toc)
        return titles
    }

    private func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        return decoded.split(separator: "#").first.map(String.init) ?? decoded
    }

    // MARK: - Image Extraction

    private nonisolated func extractAndSaveEPUBCover(epub: EPUBDocument, documentId: UUID) {
        // Look for cover image in manifest
        // Priority: 1) Item with "cover-image" property, 2) Item with id/path containing "cover"
        let manifestItems = Array(epub.manifest.items.values)

        // First, try to find item with cover-image property (EPUB 3)
        var coverItem: EPUBManifestItem?

        // Check for items with "cover" in id or path
        if coverItem == nil {
            coverItem = manifestItems.first { item in
                let isImage = isImageMediaType(item.mediaType)
                let hasCoverInId = item.id.lowercased().contains("cover")
                let hasCoverInPath = item.path.lowercased().contains("cover")
                return isImage && (hasCoverInId || hasCoverInPath)
            }
        }

        guard let item = coverItem else { return }

        let imageURL = epub.contentDirectory.appendingPathComponent(item.path)
        guard let imageData = try? Data(contentsOf: imageURL),
              let image = UIImage(data: imageData),
              let coverData = compressToJPEG(image, maxDimension: ImageConstants.coverMaxDimension) else {
            return
        }

        do {
            try imageStorage.saveCoverImage(coverData, for: documentId)
        } catch {
            print("[CanonicalParsingService] Failed to save EPUB cover for \(documentId): \(error)")
        }
    }

    private nonisolated func extractAndSaveEPUBImages(epub: EPUBDocument, documentId: UUID) {
        let manifestItems = Array(epub.manifest.items.values)
        let imageItems = manifestItems.filter { isImageMediaType($0.mediaType) }

        for (index, item) in imageItems.prefix(50).enumerated() {  // Limit to 50 images
            let imageURL = epub.contentDirectory.appendingPathComponent(item.path)
            guard let imageData = try? Data(contentsOf: imageURL),
                  let image = UIImage(data: imageData),
                  let compressedData = compressToJPEG(image, maxDimension: ImageConstants.articleImageMaxDimension) else {
                continue
            }

            let imageId = UUID()
            do {
                try imageStorage.saveImage(compressedData, imageId: imageId, bookId: documentId)
            } catch {
                print("[CanonicalParsingService] Failed to save EPUB image \(index) for \(documentId): \(error)")
            }

            // Note: The caller will need to add metadata to AppState
            // We store images but metadata tracking happens at a higher level
            saveImageMetadata(imageId: imageId, documentId: documentId, pageIndex: index, wordIndex: 0)
        }
    }

    private nonisolated func extractAndSavePDFCover(document: PDFDocument, documentId: UUID) {
        guard let firstPage = document.page(at: 0) else { return }

        // Render first page as thumbnail
        let pageRect = firstPage.bounds(for: .mediaBox)
        let scale = min(ImageConstants.coverMaxDimension / pageRect.width,
                        ImageConstants.coverMaxDimension / pageRect.height)
        let thumbnailSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        let thumbnail = firstPage.thumbnail(of: thumbnailSize, for: .mediaBox)
        guard let coverData = compressToJPEG(thumbnail, maxDimension: ImageConstants.coverMaxDimension) else {
            return
        }

        do {
            try imageStorage.saveCoverImage(coverData, for: documentId)
        } catch {
            print("[CanonicalParsingService] Failed to save PDF cover for \(documentId): \(error)")
        }
    }

    private func extractAndSaveWebImages(htmlContent: String, baseURL: URL, documentId: UUID) async {
        // Parse img tags from HTML
        let imageURLs = extractImageURLs(from: htmlContent, baseURL: baseURL)

        var isFirstImage = true
        for (index, imageURL) in imageURLs.prefix(20).enumerated() {  // Limit to 20 images
            guard let imageData = await downloadImage(from: imageURL),
                  let image = UIImage(data: imageData) else {
                continue
            }

            // Save first image as cover
            if isFirstImage {
                if let coverData = compressToJPEG(image, maxDimension: ImageConstants.coverMaxDimension) {
                    do {
                        try imageStorage.saveCoverImage(coverData, for: documentId)
                    } catch {
                        print("[CanonicalParsingService] Failed to save web cover for \(documentId): \(error)")
                    }
                }
                isFirstImage = false
            }

            // Save as document image for artifacts
            if let compressedData = compressToJPEG(image, maxDimension: ImageConstants.articleImageMaxDimension) {
                let imageId = UUID()
                do {
                    try imageStorage.saveImage(compressedData, imageId: imageId, bookId: documentId)
                } catch {
                    print("[CanonicalParsingService] Failed to save web image \(index) for \(documentId): \(error)")
                }
                saveImageMetadata(imageId: imageId, documentId: documentId, pageIndex: 0, wordIndex: index)
            }
        }
    }

    private nonisolated func extractImageURLs(from htmlContent: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []

        // Simple regex to extract src attributes from img tags
        let pattern = #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return urls
        }

        let range = NSRange(htmlContent.startIndex..., in: htmlContent)
        let matches = regex.matches(in: htmlContent, options: [], range: range)

        for match in matches {
            guard let srcRange = Range(match.range(at: 1), in: htmlContent) else { continue }
            let src = String(htmlContent[srcRange])

            // Skip data URLs and small icons
            if src.hasPrefix("data:") { continue }
            if src.contains("icon") || src.contains("logo") || src.contains("avatar") { continue }

            // Resolve relative URLs
            if let url = URL(string: src, relativeTo: baseURL)?.absoluteURL {
                urls.append(url)
            } else if let url = URL(string: src) {
                urls.append(url)
            }
        }

        return urls
    }

    private func downloadImage(from url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
                  contentType.hasPrefix("image/") else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private nonisolated func compressToJPEG(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        let scale: CGFloat

        if size.width > maxDimension || size.height > maxDimension {
            scale = min(maxDimension / size.width, maxDimension / size.height)
        } else {
            scale = 1.0
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage?.jpegData(compressionQuality: ImageConstants.jpegQuality)
    }

    private nonisolated func isImageMediaType(_ mediaType: EPUBMediaType) -> Bool {
        switch mediaType {
        case .jpeg, .png, .gif:
            return true
        default:
            return false
        }
    }

    private nonisolated func saveImageMetadata(imageId: UUID, documentId: UUID, pageIndex: Int, wordIndex: Int) {
        // Store metadata in UserDefaults for later retrieval by AppState
        // This is a simple approach - metadata will be picked up when the library is refreshed
        let key = "pending_images_\(documentId.uuidString)"
        var pendingImages = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []

        pendingImages.append([
            "id": imageId.uuidString,
            "documentId": documentId.uuidString,
            "pageIndex": pageIndex,
            "wordIndex": wordIndex,
            "dateFound": Date().timeIntervalSince1970
        ])

        UserDefaults.standard.set(pendingImages, forKey: key)
    }
}
