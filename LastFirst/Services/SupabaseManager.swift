import Foundation
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
            supabaseKey: anonKey
        )
    }

    // MARK: - Catalog

    func fetchCatalogItems(limit: Int = 20) async throws -> [CatalogItem] {
        guard let client else { return [] }
        let result: [CatalogItem] = try await client
            .from("catalog")
            .select()
            .limit(limit)
            .execute()
            .value
        return result
    }

    func fetchCatalogItem(id: UUID) async throws -> CatalogItem? {
        guard let client else { return nil }
        let result: CatalogItem = try await client
            .from("catalog")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
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
