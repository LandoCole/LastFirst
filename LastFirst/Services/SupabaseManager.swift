import Foundation
import Auth
import Supabase

final class SupabaseManager: @unchecked Sendable {

    static let shared = SupabaseManager()

    let client: SupabaseClient?

    private init() {
        guard let infoDictionary = Bundle.main.infoDictionary,
              let urlString = infoDictionary["SUPABASE_URL"] as? String,
              let anonKey = infoDictionary["SUPABASE_ANON_KEY"] as? String,
              !urlString.isEmpty,
              !anonKey.isEmpty,
              let url = URL(string: urlString)
        else {
            print("[SupabaseManager] Missing or invalid SUPABASE_URL / SUPABASE_ANON_KEY in Info.plist — running in local-only mode")
            client = nil
            return
        }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: .init(auth: .init(autoRefreshToken: true))
        )
    }

    // MARK: - Content (replaces Catalog)

    func fetchContentItems(limit: Int = 20) async throws -> [ContentItem] {
        guard let client else { return [] }
        let result: [ContentItem] = try await client
            .from("content")
            .select()
            .eq("is_available", value: true)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return result
    }

    func fetchContentItem(id: UUID) async throws -> ContentItem? {
        guard let client else { return nil }
        let result: ContentItem = try await client
            .from("content")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return result
    }

    /// Legacy catalog support — reads from content table, maps to CatalogItem
    func fetchCatalogItems(limit: Int = 20) async throws -> [CatalogItem] {
        let items = try await fetchContentItems(limit: limit)
        return items.map { $0.asCatalogItem }
    }

    func fetchCatalogItem(id: UUID) async throws -> CatalogItem? {
        let item = try await fetchContentItem(id: id)
        return item?.asCatalogItem
    }

    // MARK: - Curations

    func fetchTodaysCuration(userId: UUID) async throws -> Curation? {
        guard let client else { return nil }
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        let results: [Curation] = try await client
            .from("curations")
            .select()
            .eq("user_id", value: userId)
            .eq("type", value: "daily")
            .eq("status", value: "ready")
            .gte("created_at", value: today)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return results.first
    }

    func fetchCuration(id: UUID) async throws -> Curation? {
        guard let client else { return nil }
        let result: Curation = try await client
            .from("curations")
            .select("*")
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return result
    }

    func fetchTodaysPendingCuration(userId: UUID) async throws -> Curation? {
        guard let client else { return nil }
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        let results: [Curation] = try await client
            .from("curations")
            .select()
            .eq("user_id", value: userId)
            .eq("type", value: "daily")
            .eq("status", value: "researching")
            .gte("created_at", value: today)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return results.first
    }

    func fetchCurationItems(curationId: UUID) async throws -> [CurationItem] {
        guard let client else { return [] }
        let result: [CurationItem] = try await client
            .from("curation_items")
            .select("*, content:content_id(*)")
            .eq("curation_id", value: curationId)
            .order("position", ascending: true)
            .execute()
            .value
        return result
    }

    func fetchCurationMessages(curationId: UUID) async throws -> [CurationMessage] {
        guard let client else { return [] }
        let result: [CurationMessage] = try await client
            .from("curation_messages")
            .select()
            .eq("curation_id", value: curationId)
            .neq("role", value: "tool")
            .order("created_at", ascending: true)
            .execute()
            .value
        return result
    }

    func fetchToolMessages(curationId: UUID) async throws -> [CurationMessage] {
        guard let client else { return [] }
        let result: [CurationMessage] = try await client
            .from("curation_messages")
            .select()
            .eq("curation_id", value: curationId)
            .eq("role", value: "tool")
            .order("created_at", ascending: true)
            .execute()
            .value
        return result
    }

    func fetchLatestResearchingCuration(userId: UUID) async throws -> UUID? {
        guard let client else { return nil }
        let result: [Curation] = try await client
            .from("curations")
            .select("id")
            .eq("user_id", value: userId)
            .eq("status", value: "researching")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return result.first?.id
    }

    func fetchPastCurations(userId: UUID, limit: Int = 20) async throws -> [Curation] {
        guard let client else { return [] }
        let result: [Curation] = try await client
            .from("curations")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return result
    }

    // MARK: - Daily Curations (Timeline)

    /// Cursor-paginated daily curations (type=daily, status=ready)
    func fetchDailyCurations(userId: UUID, before: Date? = nil, limit: Int = 7) async throws -> [Curation] {
        guard let client else { return [] }
        var query = client
            .from("curations")
            .select()
            .eq("user_id", value: userId)
            .eq("type", value: "daily")
            .eq("status", value: "ready")

        if let before {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            query = query.lt("created_at", value: formatter.string(from: before))
        }

        let result: [Curation] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return result
    }

    /// Batch-fetch curation items for multiple curation IDs (avoids N+1)
    func fetchCurationItemsBatch(curationIds: [UUID]) async throws -> [UUID: [CurationItem]] {
        guard let client, !curationIds.isEmpty else { return [:] }
        let ids = curationIds.map(\.uuidString)
        let result: [CurationItem] = try await client
            .from("curation_items")
            .select("*, content:content_id(*)")
            .in("curation_id", values: ids)
            .order("position", ascending: true)
            .execute()
            .value

        var grouped: [UUID: [CurationItem]] = [:]
        for item in result {
            grouped[item.curationId, default: []].append(item)
        }
        return grouped
    }

    // MARK: - Curator Chat (Edge Function)

    struct CuratorChatRequest: Codable {
        let curationId: UUID?
        let message: String
        let userId: String
        let model: String?

        enum CodingKeys: String, CodingKey {
            case message, model
            case curationId = "curation_id"
            case userId = "user_id"
        }
    }

    struct CuratorChatResponse: Codable {
        let curationId: UUID
        let response: String?
        let itemsAdded: Int?
        let complexity: String?
        let agentCount: Int?

        enum CodingKeys: String, CodingKey {
            case response, complexity
            case curationId = "curation_id"
            case itemsAdded = "items_added"
            case agentCount = "agent_count"
        }
    }

    func sendCuratorMessage(curationId: UUID?, message: String, userId: UUID, model: String? = nil) async throws -> CuratorChatResponse {
        guard let client else {
            throw NSError(domain: "SupabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not initialized"])
        }

        let requestBody = CuratorChatRequest(
            curationId: curationId,
            message: message,
            userId: userId.uuidString,
            model: model
        )

        let response: CuratorChatResponse = try await client.functions
            .invoke("curator-chat", options: .init(body: requestBody))

        return response
    }

    // MARK: - Interactions

    struct InteractionInsert: Codable {
        let userId: UUID
        let contentId: UUID
        let kind: String

        enum CodingKeys: String, CodingKey {
            case kind
            case userId = "user_id"
            case contentId = "content_id"
        }
    }

    func postInteraction(userId: UUID, contentId: UUID, kind: String) async throws {
        guard let client else { return }
        try await client
            .from("interactions")
            .insert(InteractionInsert(userId: userId, contentId: contentId, kind: kind))
            .execute()
    }

    // MARK: - Curation Item Updates

    func markCurationItemSaved(itemId: UUID) async throws {
        guard let client else { return }
        try await client
            .from("curation_items")
            .update(["saved_to_library": true])
            .eq("id", value: itemId)
            .execute()
    }

    // MARK: - Scrape URL (Firecrawl Edge Function)

    struct ScrapeResult: Codable {
        let title: String
        let content: String
        let markdown: String
        let textContent: String
        let byline: String?
        let siteName: String?
        let language: String?
        let sourceUrl: String
    }

    private struct ScrapeRequest: Codable {
        let url: String
        let formats: [String]
    }

    func scrapeURL(url: URL) async throws -> ScrapeResult {
        guard let client else {
            throw NSError(domain: "SupabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not initialized"])
        }

        let requestBody = ScrapeRequest(url: url.absoluteString, formats: ["markdown", "html"])

        let result: ScrapeResult = try await client.functions
            .invoke("scrape-url", options: .init(body: requestBody))

        return result
    }

    // MARK: - Summarize Content (Edge Function)

    enum SummarizationPreset: String, Codable, CaseIterable {
        case quick
        case simple
        case custom
    }

    struct SummarizationResult: Codable {
        let summary: String
        let wordCount: Int
    }

    private struct SummarizeRequest: Codable {
        let text: String
        let preset: String
        let customInstructions: String?
        let model: String
    }

    func summarizeContent(
        text: String,
        preset: SummarizationPreset,
        customInstructions: String? = nil,
        model: String
    ) async throws -> SummarizationResult {
        guard let client else {
            throw NSError(domain: "SupabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not initialized"])
        }

        let requestBody = SummarizeRequest(
            text: text,
            preset: preset.rawValue,
            customInstructions: customInstructions,
            model: model
        )

        let result: SummarizationResult = try await client.functions
            .invoke("summarize-content", options: .init(body: requestBody))

        return result
    }

    // MARK: - Reading Sessions

    func upsertReadingSessions(_ dtos: [ReadingSessionDTO]) async throws {
        guard let client else { return }
        try await client
            .from("reading_sessions")
            .upsert(dtos)
            .execute()
    }

    func fetchUserStats(userId: UUID) async throws -> UserReadingStatsDTO? {
        guard let client else { return nil }
        let result: [UserReadingStatsDTO] = try await client
            .from("user_reading_stats")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        return result.first
    }

    func fetchReadingStreak(userId: UUID) async throws -> ReadingStreakDTO? {
        guard let client else { return nil }
        let result: [ReadingStreakDTO] = try await client
            .rpc("get_reading_streak", params: ["p_user_id": userId])
            .execute()
            .value
        return result.first
    }
}
