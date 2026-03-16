import Foundation
import CoreGraphics

struct ReaderDocument: Identifiable, Codable, Sendable {
    let id: UUID
    var source: DocumentSource
    var metadata: DocumentMetadata
    var toc: [TOCEntry]
    var chapters: [Chapter]
    var sections: [ReaderSection]
    var blocks: [TextBlock]
    var tokens: [Token]
    var resources: [ResourceRef]
    var buildInfo: BuildInfo

    init(
        id: UUID = UUID(),
        source: DocumentSource,
        metadata: DocumentMetadata,
        toc: [TOCEntry] = [],
        chapters: [Chapter] = [],
        sections: [ReaderSection] = [],
        blocks: [TextBlock] = [],
        tokens: [Token] = [],
        resources: [ResourceRef] = [],
        buildInfo: BuildInfo = BuildInfo()
    ) {
        self.id = id
        self.source = source
        self.metadata = metadata
        self.toc = toc
        self.chapters = chapters
        self.sections = sections
        self.blocks = blocks
        self.tokens = tokens
        self.resources = resources
        self.buildInfo = buildInfo
    }
}

struct Chapter: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var startWordIndex: Int
    var endWordIndex: Int

    init(id: UUID = UUID(), title: String, startWordIndex: Int, endWordIndex: Int) {
        self.id = id
        self.title = title
        self.startWordIndex = startWordIndex
        self.endWordIndex = endWordIndex
    }
}

struct DocumentMetadata: Codable, Sendable {
    var title: String
    var author: String?
    var languageCode: String?
    var createdAt: Date
    var lastUpdatedAt: Date

    init(
        title: String,
        author: String? = nil,
        languageCode: String? = nil,
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.title = title
        self.author = author
        self.languageCode = languageCode
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}

enum DocumentSource: Codable, Equatable, Sendable {
    case localFile(LocalFileSource)
    case web(WebSource)

    struct LocalFileSource: Codable, Equatable, Sendable {
        var url: URL
        var fileType: LocalFileType

        init(url: URL, fileType: LocalFileType) {
            self.url = url
            self.fileType = fileType
        }
    }

    enum LocalFileType: String, Codable, CaseIterable, Sendable {
        case epub
        case pdf
    }

    struct WebSource: Codable, Equatable, Sendable {
        var url: URL
        var lastRefreshedAt: Date?

        init(url: URL, lastRefreshedAt: Date? = nil) {
            self.url = url
            self.lastRefreshedAt = lastRefreshedAt
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case localFile
        case web
    }

    private enum SourceType: String, Codable {
        case localFile
        case web
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SourceType.self, forKey: .type)
        switch type {
        case .localFile:
            self = .localFile(try container.decode(LocalFileSource.self, forKey: .localFile))
        case .web:
            self = .web(try container.decode(WebSource.self, forKey: .web))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .localFile(let value):
            try container.encode(SourceType.localFile, forKey: .type)
            try container.encode(value, forKey: .localFile)
        case .web(let value):
            try container.encode(SourceType.web, forKey: .type)
            try container.encode(value, forKey: .web)
        }
    }
}

struct ReaderSection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var blockRange: Range<Int>

    init(id: UUID = UUID(), title: String, blockRange: Range<Int>) {
        self.id = id
        self.title = title
        self.blockRange = blockRange
    }
}

struct TextBlock: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var sectionIndex: Int
    var kind: BlockKind
    var rawText: String
    var tokenRange: Range<Int>
    var sourceLocation: DocumentLocation?

    init(
        id: UUID = UUID(),
        sectionIndex: Int,
        kind: BlockKind,
        rawText: String,
        tokenRange: Range<Int>,
        sourceLocation: DocumentLocation? = nil
    ) {
        self.id = id
        self.sectionIndex = sectionIndex
        self.kind = kind
        self.rawText = rawText
        self.tokenRange = tokenRange
        self.sourceLocation = sourceLocation
    }
}

enum BlockKind: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading
    case listItem
    case quote
    case code
}

struct Token: Codable, Equatable, Sendable {
    var id: Int
    var text: String
    var kind: TokenKind
    var blockIndex: Int
    var sentenceIndex: Int
    var sourceLocation: DocumentLocation?

    init(
        id: Int,
        text: String,
        kind: TokenKind,
        blockIndex: Int,
        sentenceIndex: Int,
        sourceLocation: DocumentLocation? = nil
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.blockIndex = blockIndex
        self.sentenceIndex = sentenceIndex
        self.sourceLocation = sourceLocation
    }
}

enum TokenKind: String, Codable, CaseIterable, Sendable {
    case word
    case punctuation
    case paragraphBreak
    case chapterTitle
    case sectionTitle
    case epigraph
    case footnoteRef
    case listBullet
    case imageAlt
}

struct TOCEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var location: DocumentLocation
    var children: [TOCEntry]

    init(id: UUID = UUID(), title: String, location: DocumentLocation, children: [TOCEntry] = []) {
        self.id = id
        self.title = title
        self.location = location
        self.children = children
    }
}

struct ResourceRef: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ResourceKind
    var sourceLocation: DocumentLocation?
    var dataURL: URL?

    init(id: UUID = UUID(), kind: ResourceKind, sourceLocation: DocumentLocation? = nil, dataURL: URL? = nil) {
        self.id = id
        self.kind = kind
        self.sourceLocation = sourceLocation
        self.dataURL = dataURL
    }
}

enum ResourceKind: String, Codable, CaseIterable, Sendable {
    case image
}

struct BuildInfo: Codable, Equatable, Sendable {
    var ingestionVersion: Int
    var builtAt: Date

    init(ingestionVersion: Int = 1, builtAt: Date = Date()) {
        self.ingestionVersion = ingestionVersion
        self.builtAt = builtAt
    }
}

enum DocumentLocation: Codable, Equatable, Sendable {
    case epub(EPUBLocation)
    case web(WebLocation)
    case markdown(MarkdownLocation)
    case pdf(PDFLocation)

    struct EPUBLocation: Codable, Equatable, Sendable {
        var spineHref: String
        var progression: Double?
        var cfi: String?

        init(spineHref: String, progression: Double? = nil, cfi: String? = nil) {
            self.spineHref = spineHref
            self.progression = progression
            self.cfi = cfi
        }
    }

    struct WebLocation: Codable, Equatable, Sendable {
        var url: URL
        var domPath: String?
        var textOffset: Int?

        init(url: URL, domPath: String? = nil, textOffset: Int? = nil) {
            self.url = url
            self.domPath = domPath
            self.textOffset = textOffset
        }
    }

    struct MarkdownLocation: Codable, Equatable, Sendable {
        var fileURL: URL
        var headingAnchor: String?
        var textOffset: Int?

        init(fileURL: URL, headingAnchor: String? = nil, textOffset: Int? = nil) {
            self.fileURL = fileURL
            self.headingAnchor = headingAnchor
            self.textOffset = textOffset
        }
    }

    struct PDFLocation: Codable, Equatable, Sendable {
        var fileURL: URL
        var pageIndex: Int
        var rect: CodableRect?

        init(fileURL: URL, pageIndex: Int, rect: CodableRect? = nil) {
            self.fileURL = fileURL
            self.pageIndex = pageIndex
            self.rect = rect
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case epub
        case web
        case markdown
        case pdf
    }

    private enum LocationType: String, Codable, Sendable {
        case epub
        case web
        case markdown
        case pdf
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(LocationType.self, forKey: .type)
        switch type {
        case .epub:
            self = .epub(try container.decode(EPUBLocation.self, forKey: .epub))
        case .web:
            self = .web(try container.decode(WebLocation.self, forKey: .web))
        case .markdown:
            self = .markdown(try container.decode(MarkdownLocation.self, forKey: .markdown))
        case .pdf:
            self = .pdf(try container.decode(PDFLocation.self, forKey: .pdf))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .epub(let value):
            try container.encode(LocationType.epub, forKey: .type)
            try container.encode(value, forKey: .epub)
        case .web(let value):
            try container.encode(LocationType.web, forKey: .type)
            try container.encode(value, forKey: .web)
        case .markdown(let value):
            try container.encode(LocationType.markdown, forKey: .type)
            try container.encode(value, forKey: .markdown)
        case .pdf(let value):
            try container.encode(LocationType.pdf, forKey: .type)
            try container.encode(value, forKey: .pdf)
        }
    }
}

struct CodableRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct ReadingProgress: Codable, Equatable, Sendable {
    var tokenIndex: Int
    var percentComplete: Double

    init(tokenIndex: Int = 0, percentComplete: Double = 0) {
        self.tokenIndex = tokenIndex
        self.percentComplete = percentComplete
    }
}

struct Annotation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var documentId: UUID
    var kind: AnnotationKind
    var range: AnnotationRange
    var title: String?
    var excerpt: String?
    var note: String?
    var createdAt: Date
    var lastUpdatedAt: Date

    init(
        id: UUID = UUID(),
        documentId: UUID,
        kind: AnnotationKind,
        range: AnnotationRange,
        title: String? = nil,
        excerpt: String? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.documentId = documentId
        self.kind = kind
        self.range = range
        self.title = title
        self.excerpt = excerpt
        self.note = note
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}

enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case highlight
    case bookmark
    case note
}

struct AnnotationRange: Codable, Equatable, Sendable {
    var start: DocumentAnchor
    var end: DocumentAnchor

    init(start: DocumentAnchor, end: DocumentAnchor) {
        self.start = start
        self.end = end
    }
}

struct DocumentAnchor: Codable, Equatable, Sendable {
    var tokenIndex: Int
    var location: DocumentLocation?

    init(tokenIndex: Int, location: DocumentLocation? = nil) {
        self.tokenIndex = tokenIndex
        self.location = location
    }
}

enum CanonicalDocumentType: String, Codable, Sendable {
    case epub
    case pdf
    case web
}

struct DocumentIdentifier: Hashable, Codable, Sendable {
    var scheme: String
    var value: String

    init(scheme: String, value: String) {
        self.scheme = scheme
        self.value = value
    }
}

struct DocumentManifest: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var authors: [String]
    var languageCode: String?
    var identifiers: [DocumentIdentifier]
    var documentType: CanonicalDocumentType
    var parserVersion: Int
    var normalizerVersion: Int
    var segmenterVersion: Int
    var createdAt: Date
    var lastUpdatedAt: Date

    init(
        id: UUID,
        title: String,
        authors: [String] = [],
        languageCode: String? = nil,
        identifiers: [DocumentIdentifier] = [],
        documentType: CanonicalDocumentType,
        parserVersion: Int,
        normalizerVersion: Int,
        segmenterVersion: Int,
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.languageCode = languageCode
        self.identifiers = identifiers
        self.documentType = documentType
        self.parserVersion = parserVersion
        self.normalizerVersion = normalizerVersion
        self.segmenterVersion = segmenterVersion
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}

enum ReadingUnitKind: String, Codable, Sendable {
    case chapter
    case article
    case document
}

struct ReadingUnit: Identifiable, Codable, Sendable {
    var id: String
    var title: String
    var kind: ReadingUnitKind
    var order: Int

    init(id: String, title: String, kind: ReadingUnitKind, order: Int) {
        self.id = id
        self.title = title
        self.kind = kind
        self.order = order
    }
}

enum ContentSegmentKind: String, Codable, Sendable {
    case headingGroup
    case paragraphGroup
    case page
}

enum StructuralContentKind: String, Codable, Sendable {
    case heading1, heading2, heading3, heading4, heading5, heading6
    case paragraph, listItem, blockquote, codeBlock, image, divider
}

struct FootnoteRecord: Codable, Sendable, Identifiable {
    var id: String
    var refText: String
    var bodyText: String
    var unitID: String
}

struct PageListEntry: Codable, Sendable {
    var label: String
    var unitID: String
    var anchorID: String?
}

struct TextRange: Codable, Equatable, Sendable {
    var start: Int
    var end: Int

    init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

struct ContentSegment: Identifiable, Codable, Sendable {
    var id: String
    var unitID: String
    var anchorID: String
    var kind: ContentSegmentKind
    var order: Int
    var text: String
    var textRange: TextRange?
    var structuralKind: StructuralContentKind?

    init(
        id: String,
        unitID: String,
        anchorID: String,
        kind: ContentSegmentKind,
        order: Int,
        text: String,
        textRange: TextRange? = nil,
        structuralKind: StructuralContentKind? = nil
    ) {
        self.id = id
        self.unitID = unitID
        self.anchorID = anchorID
        self.kind = kind
        self.order = order
        self.text = text
        self.textRange = textRange
        self.structuralKind = structuralKind
    }
}

enum RenderFormat: String, Codable, Sendable {
    case html
    case pdf
}

struct RenderUnit: Codable, Sendable {
    var unitID: String
    var entryPath: String
    var title: String?

    init(unitID: String, entryPath: String, title: String? = nil) {
        self.unitID = unitID
        self.entryPath = entryPath
        self.title = title
    }
}

struct RenderPackage: Codable, Sendable {
    var format: RenderFormat
    var baseURL: URL
    var units: [RenderUnit]

    init(format: RenderFormat, baseURL: URL, units: [RenderUnit]) {
        self.format = format
        self.baseURL = baseURL
        self.units = units
    }
}

struct AnchorRecord: Identifiable, Codable, Sendable {
    var id: String
    var unitID: String
    var progress: Double
    var segmentID: String?

    init(id: String, unitID: String, progress: Double, segmentID: String? = nil) {
        self.id = id
        self.unitID = unitID
        self.progress = progress
        self.segmentID = segmentID
    }
}

struct TextAnchorsPackage: Codable, Sendable {
    var plainText: String
    var units: [ReadingUnit]
    var segments: [ContentSegment]
    var anchors: [AnchorRecord]
    var footnotes: [FootnoteRecord]
    var pageList: [PageListEntry]
    var parserVersion: Int
    var normalizerVersion: Int
    var segmenterVersion: Int

    init(
        plainText: String,
        units: [ReadingUnit],
        segments: [ContentSegment],
        anchors: [AnchorRecord],
        footnotes: [FootnoteRecord] = [],
        pageList: [PageListEntry] = [],
        parserVersion: Int,
        normalizerVersion: Int,
        segmenterVersion: Int
    ) {
        self.plainText = plainText
        self.units = units
        self.segments = segments
        self.anchors = anchors
        self.footnotes = footnotes
        self.pageList = pageList
        self.parserVersion = parserVersion
        self.normalizerVersion = normalizerVersion
        self.segmenterVersion = segmenterVersion
    }
}

struct Locator: Codable, Equatable, Sendable {
    var documentID: UUID
    var unitID: String
    var anchorID: String
    var progress: Double
    var quote: String
    var contextBefore: String
    var contextAfter: String

    init(
        documentID: UUID,
        unitID: String,
        anchorID: String,
        progress: Double,
        quote: String,
        contextBefore: String,
        contextAfter: String
    ) {
        self.documentID = documentID
        self.unitID = unitID
        self.anchorID = anchorID
        self.progress = progress
        self.quote = quote
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

struct CanonicalDocumentPackages: Codable, Sendable {
    var manifest: DocumentManifest
    var renderPackage: RenderPackage
    var textAnchorsPackage: TextAnchorsPackage

    init(manifest: DocumentManifest, renderPackage: RenderPackage, textAnchorsPackage: TextAnchorsPackage) {
        self.manifest = manifest
        self.renderPackage = renderPackage
        self.textAnchorsPackage = textAnchorsPackage
    }
}

 enum SpeedCleanProfile: String, Codable, Sendable {
     case book
     case article
     case pdfPaper
 }

 enum SpeedCleanDeliveryMode: String, Codable, Sendable {
     case onDevice
     case serverFallback
     case hybrid
 }

 enum SpeedCleanChunkStatus: String, Codable, Sendable {
     case notStarted
     case processing
     case ready
     case failed
 }

 enum SpeedCleanOverallStatus: String, Codable, Sendable {
     case notStarted
     case processing
     case partial
     case ready
     case failed
 }

 struct SpeedCleanChunk: Identifiable, Codable, Sendable {
     var id: String { segmentID }
     var segmentID: String
     var unitID: String
     var cleanedText: String
     var status: SpeedCleanChunkStatus
     var deliveryMode: SpeedCleanDeliveryMode?
     var updatedAt: Date

     init(
         segmentID: String,
         unitID: String,
         cleanedText: String,
         status: SpeedCleanChunkStatus,
         deliveryMode: SpeedCleanDeliveryMode? = nil,
         updatedAt: Date = Date()
     ) {
         self.segmentID = segmentID
         self.unitID = unitID
         self.cleanedText = cleanedText
         self.status = status
         self.deliveryMode = deliveryMode
         self.updatedAt = updatedAt
     }
 }

 struct SpeedCleanPackage: Codable, Sendable {
     var documentId: UUID
     var profile: SpeedCleanProfile
     var deliveryMode: SpeedCleanDeliveryMode
     var status: SpeedCleanOverallStatus
     var chunks: [SpeedCleanChunk]
     var createdAt: Date
     var updatedAt: Date

     init(
         documentId: UUID,
         profile: SpeedCleanProfile,
         deliveryMode: SpeedCleanDeliveryMode = .onDevice,
         status: SpeedCleanOverallStatus = .notStarted,
         chunks: [SpeedCleanChunk],
         createdAt: Date = Date(),
         updatedAt: Date = Date()
     ) {
         self.documentId = documentId
         self.profile = profile
         self.deliveryMode = deliveryMode
         self.status = status
         self.chunks = chunks
         self.createdAt = createdAt
         self.updatedAt = updatedAt
     }

     func chunk(for segmentID: String) -> SpeedCleanChunk? {
         chunks.first(where: { $0.segmentID == segmentID })
     }

     func isUnitReady(_ unitID: String, segmentIDs: [String]) -> Bool {
         unitStatus(unitID, segmentIDs: segmentIDs) == .ready
     }

     func unitStatus(_ unitID: String, segmentIDs: [String]) -> SpeedCleanOverallStatus {
         let relevantSegmentIDs = Set(segmentIDs)
         guard !relevantSegmentIDs.isEmpty else { return .notStarted }
         let relevantChunks = chunks.filter {
             $0.unitID == unitID && relevantSegmentIDs.contains($0.segmentID)
         }
         guard !relevantChunks.isEmpty else {
             return .notStarted
         }

         if relevantChunks.allSatisfy({ $0.status == .ready }) && Set(relevantChunks.map(\.segmentID)) == relevantSegmentIDs {
             return .ready
         }
         if relevantChunks.contains(where: { $0.status == .processing }) {
             return .processing
         }
         if relevantChunks.contains(where: { $0.status == .ready }) {
             return .partial
         }
         if relevantChunks.contains(where: { $0.status == .failed }) {
             return .failed
         }
         return .notStarted
     }
 }

