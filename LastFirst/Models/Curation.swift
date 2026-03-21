import Foundation

struct Curation: Identifiable, Codable, Equatable {
    let id: UUID
    var userId: UUID
    var type: String           // 'user_directed', 'daily'
    var title: String
    var prompt: String?
    var summary: String?
    var status: String         // 'pending', 'researching', 'ready', 'error'
    var errorMessage: String?
    var expiresAt: Date?
    var isPublic: Bool?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, title, prompt, summary, status
        case userId = "user_id"
        case errorMessage = "error_message"
        case expiresAt = "expires_at"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CurationItem: Identifiable, Codable, Equatable {
    let id: UUID
    var curationId: UUID
    var contentId: UUID?
    var externalUrl: String?
    var externalTitle: String?
    var externalAuthor: String?
    var externalSummary: String?
    var agentNote: String?
    var itemType: String       // 'content', 'external_link', 'book', 'article', 'paper', 'pdf'
    var position: Int
    var savedToLibrary: Bool?
    var createdAt: Date?
    var extractedText: String?
    var externalWordCount: Int?
    var externalEstimatedReadMinutes: Int?
    var externalFileType: String?
    var externalAvailability: String?
    var externalImageUrl: String?

    // Joined content (optional, populated when fetching with select)
    var content: ContentItem?

    enum CodingKeys: String, CodingKey {
        case id, content, position
        case curationId = "curation_id"
        case contentId = "content_id"
        case externalUrl = "external_url"
        case externalTitle = "external_title"
        case externalAuthor = "external_author"
        case externalSummary = "external_summary"
        case agentNote = "agent_note"
        case itemType = "item_type"
        case savedToLibrary = "saved_to_library"
        case createdAt = "created_at"
        case extractedText = "extracted_text"
        case externalWordCount = "external_word_count"
        case externalEstimatedReadMinutes = "external_estimated_read_minutes"
        case externalFileType = "external_file_type"
        case externalAvailability = "external_availability"
        case externalImageUrl = "external_image_url"
    }

    var displayTitle: String {
        content?.title ?? externalTitle ?? "Untitled"
    }

    var displayAuthor: String? {
        content?.author ?? externalAuthor
    }

    var displaySummary: String? {
        content?.summary ?? externalSummary
    }

    var displayWordCount: Int? {
        content?.wordCount ?? externalWordCount
    }

    var displayEstimatedReadMinutes: Int? {
        content?.estimatedReadMinutes ?? externalEstimatedReadMinutes
            ?? displayWordCount.map { max(1, $0 / 250) }
    }

    var displayFileType: String? {
        content?.fileType ?? externalFileType
            ?? (itemType != "content" && itemType != "external_link" ? itemType : "web")
    }

    var displayAvailability: String? {
        content?.availability ?? externalAvailability
            ?? (itemType == "external_link" || itemType == "book" ? "external_purchase" : nil)
    }

    var displayImageUrl: URL? {
        if let s = content?.coverUrl ?? externalImageUrl {
            return URL(string: s)
        }
        return nil
    }
}

// MARK: - Curator Status Protocol

enum CuratorStatusType: String, Codable {
    case plan
    case stepStart = "step_start"
    case stepProgress = "step_progress"
    case stepComplete = "step_complete"
    case finding
    case error
    // Multi-agent status types
    case agentSpawned = "agent_spawned"
    case agentProgress = "agent_progress"
    case agentComplete = "agent_complete"
    case synthesisStart = "synthesis_start"
}

struct CuratorStatusMessage: Codable {
    let type: CuratorStatusType
    let plan: [CuratorPlanStepDTO]?
    let stepIndex: Int?
    let tool: String?
    let message: String?
    let detail: String?
    let finding: String?
    let title: String?
    // Multi-agent fields
    let agentRole: String?
    let agentTaskId: String?
    let totalAgents: Int?
    let completedAgents: Int?

    struct CuratorPlanStepDTO: Codable {
        let label: String
        let description: String
    }
}

enum CuratorStepState: Equatable {
    case pending, active, complete
}

struct CuratorPlanStep: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let description: String
    var state: CuratorStepState = .pending
    var finding: String?
}

struct AgentProgress: Identifiable, Equatable {
    let id: UUID
    let role: String
    var state: CuratorStepState = .pending
    var finding: String?
}

struct CuratorResearchPlan: Equatable {
    var steps: [CuratorPlanStep] = []
    var currentStepIndex: Int? = nil
    var agents: [AgentProgress] = []
}

// MARK: - Curation Messages

struct CurationMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var curationId: UUID
    var role: String           // 'user', 'assistant', 'system', 'tool'
    var content: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case curationId = "curation_id"
        case createdAt = "created_at"
    }
}
