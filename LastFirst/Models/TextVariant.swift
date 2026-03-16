import Foundation

enum TextVariantKind: String, Codable, Sendable, CaseIterable {
    case speedClean
    case summary
    case custom
    case audio
}

enum TextVariantStatus: String, Codable, Sendable {
    case queued
    case processing
    case ready
    case failed
}

enum SummaryConciseness: String, Codable, Sendable, CaseIterable {
    case brief
    case moderate
    case detailed

    var displayName: String {
        switch self {
        case .brief: return "Brief"
        case .moderate: return "Moderate"
        case .detailed: return "Detailed"
        }
    }
}

struct TextVariantChunk: Codable, Sendable {
    var segmentID: String
    var unitID: String
    var transformedText: String
    var status: TextVariantStatus
    var updatedAt: Date

    init(
        segmentID: String,
        unitID: String,
        transformedText: String,
        status: TextVariantStatus,
        updatedAt: Date = Date()
    ) {
        self.segmentID = segmentID
        self.unitID = unitID
        self.transformedText = transformedText
        self.status = status
        self.updatedAt = updatedAt
    }
}

struct TextVariant: Identifiable, Codable, Sendable {
    let id: UUID
    var documentId: UUID
    var unitID: String
    var name: String
    var kind: TextVariantKind
    var instructions: String?
    var chunks: [TextVariantChunk]
    var status: TextVariantStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        documentId: UUID,
        unitID: String,
        name: String,
        kind: TextVariantKind,
        instructions: String? = nil,
        chunks: [TextVariantChunk] = [],
        status: TextVariantStatus = .queued,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.documentId = documentId
        self.unitID = unitID
        self.name = name
        self.kind = kind
        self.instructions = instructions
        self.chunks = chunks
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct TextVariantPackage: Codable, Sendable {
    var documentId: UUID
    var variants: [TextVariant]
    var createdAt: Date
    var updatedAt: Date

    init(
        documentId: UUID,
        variants: [TextVariant] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.documentId = documentId
        self.variants = variants
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
