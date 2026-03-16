import Foundation

struct ChapterInfo: Identifiable, Sendable {
    let id: String
    let title: String
    let order: Int
    let segmentCount: Int
    let wordCount: Int
}

enum MessageRole: Sendable {
    case user
    case assistant
}

struct AIMenuMessage: Identifiable {
    let id: UUID
    var role: MessageRole
    var content: String
    var variant: TextVariant?
    var timestamp: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        variant: TextVariant? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.variant = variant
        self.timestamp = timestamp
    }
}

@MainActor
final class AIMenuViewModel: ObservableObject {
    @Published var chapters: [ChapterInfo] = []
    @Published var selectedChapter: ChapterInfo?
    @Published var messages: [AIMenuMessage] = []
    @Published var variants: [TextVariant] = []
    @Published var isProcessing = false
    @Published var inputText: String = ""
    @Published var error: String?

    let documentId: UUID
    var canonicalPackages: CanonicalDocumentPackages?
    var documentSource: DocumentSource?

    init(documentId: UUID) {
        self.documentId = documentId
    }

    func loadChaptersAndVariants(canonicalPackages: CanonicalDocumentPackages?) async {
        self.canonicalPackages = canonicalPackages
    }

    func requestSpeedClean(unitID: String) async {
    }

    func requestSummary(unitID: String, conciseness: SummaryConciseness) async {
    }

    func requestCustom(unitID: String, instructions: String) async {
    }

    func deleteVariant(_ variant: TextVariant) async {
    }

    func variantsForUnit(_ unitID: String) -> [TextVariant] {
        variants.filter { $0.unitID == unitID }
    }
}
