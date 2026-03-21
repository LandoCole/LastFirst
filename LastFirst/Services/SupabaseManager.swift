import Foundation
import Auth
import Supabase

final class SupabaseManager: @unchecked Sendable {

    static let shared = SupabaseManager()

    let client: SupabaseClient?

    var hasAuthenticatedSession: Bool {
        guard let client, let session = client.auth.currentSession else { return false }
        return !session.isExpired
    }

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

    private func authenticatedEdgeFunctionsClient(functionName: String) async throws -> SupabaseClient {
        guard let client else {
            throw NSError(domain: "SupabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not initialized"])
        }

        guard client.auth.currentSession != nil else {
            throw NSError(
                domain: "SupabaseManager",
                code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey: "The Supabase edge function `\(functionName)` requires a signed-in session. The app is currently running without a Supabase user session, so it will stay on the local fallback path."
                ]
            )
        }

        do {
            // Always get a fresh session — this triggers token refresh if needed.
            // The SDK's .session accessor checks expiry internally and refreshes.
            let session = try await client.auth.session
            let expiresAt = Date(timeIntervalSince1970: session.expiresAt)
            let secondsRemaining = expiresAt.timeIntervalSinceNow
            print("[SupabaseManager] \(functionName): session valid, token expires in \(Int(secondsRemaining))s")
            return client
        } catch {
            throw NSError(
                domain: "SupabaseManager",
                code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey: "The Supabase edge function `\(functionName)` requires a valid signed-in session. Refreshing the current Supabase session failed, so the request was skipped. Original error: \(error.localizedDescription)"
                ]
            )
        }
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
        let model: String?

        enum CodingKeys: String, CodingKey {
            case message, model
            case curationId = "curation_id"
        }
    }

    struct CuratorChatResponse: Codable {
        let curationId: UUID
        let response: String?
        let itemsAdded: Int?
        let complexity: String?
        let agentCount: Int?
        let clarificationQuestions: [ClarificationQuestion]?

        enum CodingKeys: String, CodingKey {
            case response, complexity
            case curationId = "curation_id"
            case itemsAdded = "items_added"
            case agentCount = "agent_count"
            case clarificationQuestions = "clarification_questions"
        }
    }

    func sendCuratorMessage(curationId: UUID?, message: String, model: String? = nil) async throws -> CuratorChatResponse {
        let client = try await authenticatedEdgeFunctionsClient(functionName: "curator-chat")

        let requestBody = CuratorChatRequest(
            curationId: curationId,
            message: message,
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
        let client = try await authenticatedEdgeFunctionsClient(functionName: "scrape-url")

        let requestBody = ScrapeRequest(url: url.absoluteString, formats: ["markdown", "html"])

        do {
            let result: ScrapeResult = try await client.functions
                .invoke("scrape-url", options: .init(body: requestBody))

            return result
        } catch {
            let description = error.localizedDescription

            if description.contains("401") || description.localizedCaseInsensitiveContains("unauthorized") {
                throw NSError(
                    domain: "SupabaseManager",
                    code: 401,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The Supabase edge function `scrape-url` rejected the request with 401. This usually means the deployed function still requires JWT verification and the current app session is missing or invalid. Sign in and retry, or disable JWT verification for anonymous use. Original error: \(description)"
                    ]
                )
            }

            throw error
        }
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

    struct SpeedCleanSegmentRequest: Codable {
        let id: String
        let text: String
        let structuralKind: String?

        enum CodingKeys: String, CodingKey {
            case id, text
            case structuralKind = "structural_kind"
        }
    }

    struct SpeedCleanSegmentResult: Codable, Sendable {
        let segmentID: String
        let cleanedText: String

        enum CodingKeys: String, CodingKey {
            case segmentID = "segment_id"
            case cleanedText = "cleaned_text"
        }
    }

    private struct SpeedCleanRequest: Codable {
        let profile: String
        let unitID: String
        let unitTitle: String?
        let segments: [SpeedCleanSegmentRequest]
        let model: String?

        enum CodingKeys: String, CodingKey {
            case profile, segments, model
            case unitID = "unit_id"
            case unitTitle = "unit_title"
        }
    }

    private struct SpeedCleanResponse: Codable {
        let segments: [SpeedCleanSegmentResult]
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

    func speedCleanSegments(
        profile: SpeedCleanProfile,
        unitID: String,
        unitTitle: String?,
        segments: [ContentSegment],
        model: String? = nil
    ) async throws -> [SpeedCleanSegmentResult] {
        let client = try await authenticatedEdgeFunctionsClient(functionName: "speed-clean")

        let requestBody = SpeedCleanRequest(
            profile: profile.rawValue,
            unitID: unitID,
            unitTitle: unitTitle,
            segments: segments.map {
                SpeedCleanSegmentRequest(
                    id: $0.id,
                    text: $0.text,
                    structuralKind: $0.structuralKind?.rawValue
                )
            },
            model: model
        )

        do {
            let result: SpeedCleanResponse = try await client.functions
                .invoke("speed-clean", options: .init(body: requestBody))

            return result.segments
        } catch {
            let description = error.localizedDescription

            if description.contains("401") || description.localizedCaseInsensitiveContains("unauthorized") {
                throw NSError(
                    domain: "SupabaseManager",
                    code: 401,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The Supabase edge function `speed-clean` rejected the request with 401. This usually means the deployed function still requires JWT verification and the current app session is missing or invalid. Sign in and retry, or disable JWT verification for anonymous use. Original error: \(description)"
                    ]
                )
            }

            if description.contains("404") || description.localizedCaseInsensitiveContains("not found") {
                throw NSError(
                    domain: "SupabaseManager",
                    code: 404,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The Supabase edge function `speed-clean` returned 404. The app is reaching your Supabase project, but that function is not deployed there yet. Deploy `supabase/functions/speed-clean` to the active project, then retry. Original error: \(description)"
                    ]
                )
            }

            throw error
        }
    }

    // MARK: - Text Transform (Edge Function)

    struct TextTransformSegmentInput: Codable {
        let id: String
        let text: String
    }

    struct TextTransformSegmentResult: Codable, Sendable {
        let segmentID: String
        let transformedText: String

        enum CodingKeys: String, CodingKey {
            case segmentID = "segment_id"
            case transformedText = "transformed_text"
        }
    }

    private struct TextTransformRequest: Codable {
        let mode: String
        let conciseness: String?
        let instructions: String?
        let unitID: String
        let unitTitle: String?
        let segments: [TextTransformSegmentInput]
        let model: String?

        enum CodingKeys: String, CodingKey {
            case mode, conciseness, instructions, segments, model
            case unitID = "unit_id"
            case unitTitle = "unit_title"
        }
    }

    private struct TextTransformResponse: Codable {
        let segments: [TextTransformSegmentResult]
    }

    func textTransform(
        mode: String,
        conciseness: String?,
        instructions: String?,
        unitID: String,
        unitTitle: String?,
        segments: [TextTransformSegmentInput],
        model: String? = nil
    ) async throws -> [TextTransformSegmentResult] {
        let client = try await authenticatedEdgeFunctionsClient(functionName: "text-transform")

        let requestBody = TextTransformRequest(
            mode: mode,
            conciseness: conciseness,
            instructions: instructions,
            unitID: unitID,
            unitTitle: unitTitle,
            segments: segments,
            model: model
        )

        do {
            let result: TextTransformResponse = try await client.functions
                .invoke("text-transform", options: .init(body: requestBody))

            return result.segments
        } catch {
            let description = error.localizedDescription

            if description.contains("401") || description.localizedCaseInsensitiveContains("unauthorized") {
                throw NSError(
                    domain: "SupabaseManager",
                    code: 401,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The Supabase edge function `text-transform` rejected the request with 401. Sign in and retry. Original error: \(description)"
                    ]
                )
            }

            if description.contains("404") || description.localizedCaseInsensitiveContains("not found") {
                throw NSError(
                    domain: "SupabaseManager",
                    code: 404,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The Supabase edge function `text-transform` returned 404. Deploy `supabase/functions/text-transform` to the active project, then retry. Original error: \(description)"
                    ]
                )
            }

            throw error
        }
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
