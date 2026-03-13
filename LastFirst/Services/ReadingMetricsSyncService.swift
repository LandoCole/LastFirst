import Foundation
import SwiftData

@MainActor
class ReadingMetricsSyncService {
    private let modelContext: ModelContext
    private var syncTimer: Timer?
    private let syncIntervalSeconds: TimeInterval = 300 // 5 minutes

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Persist Session Locally

    func persistSession(_ record: ReadingSessionRecord) {
        guard record.durationSeconds > 0, record.wordsRead > 0 else { return }
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            print("[ReadingMetricsSyncService] Save session failed: \(error)")
        }
    }

    // MARK: - Sync Lifecycle

    func startPeriodicSync() {
        stopPeriodicSync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncAll()
            }
        }
    }

    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func syncAll() async {
        await pushUnsyncedSessions()
        await pullAggregatedStats()
    }

    // MARK: - Push Unsynced Sessions

    func pushUnsyncedSessions() async {
        guard let client = SupabaseManager.shared.client else { return }

        let userId: UUID
        do {
            userId = try await client.auth.session.user.id
        } catch {
            print("[ReadingMetricsSyncService] Auth session unavailable: \(error)")
            return
        }

        let predicate = #Predicate<ReadingSessionRecord> { $0.isSynced == false }
        let descriptor = FetchDescriptor<ReadingSessionRecord>(predicate: predicate)

        let unsyncedRecords: [ReadingSessionRecord]
        do {
            unsyncedRecords = try modelContext.fetch(descriptor)
        } catch {
            print("[ReadingMetricsSyncService] Fetch unsynced records failed: \(error)")
            return
        }
        guard !unsyncedRecords.isEmpty else { return }

        let dtos = unsyncedRecords.map { ReadingSessionDTO(from: $0, userId: userId) }

        do {
            try await client
                .from("reading_sessions")
                .upsert(dtos)
                .execute()

            for record in unsyncedRecords {
                record.isSynced = true
            }
            do {
                try modelContext.save()
            } catch {
                print("[ReadingMetricsSyncService] Save after sync failed: \(error)")
            }
        } catch {
            print("[ReadingMetricsSyncService] Push failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull Aggregated Stats

    func pullAggregatedStats() async {
        guard let client = SupabaseManager.shared.client else { return }

        let userId: UUID
        do {
            userId = try await client.auth.session.user.id
        } catch {
            print("[ReadingMetricsSyncService] Auth session unavailable for pull: \(error)")
            return
        }

        let userIdString = userId.uuidString

        // Fetch stats + streak in parallel
        async let statsResult: [UserReadingStatsDTO]? = {
            do {
                return try await client
                    .from("user_reading_stats")
                    .select()
                    .eq("user_id", value: userId)
                    .execute()
                    .value
            } catch {
                print("[ReadingMetricsSyncService] Fetch stats failed: \(error)")
                return nil
            }
        }()

        async let streakResult: [ReadingStreakDTO]? = {
            do {
                return try await client
                    .rpc("get_reading_streak", params: ["p_user_id": userId])
                    .execute()
                    .value
            } catch {
                print("[ReadingMetricsSyncService] Fetch streak failed: \(error)")
                return nil
            }
        }()

        guard let stats = await statsResult?.first else { return }
        let streak = await streakResult?.first

        // Upsert into local cache
        let predicate = #Predicate<ReadingStatsCache> { $0.userId == userIdString }
        let descriptor = FetchDescriptor<ReadingStatsCache>(predicate: predicate)
        let existing: [ReadingStatsCache]?
        do {
            existing = try modelContext.fetch(descriptor)
        } catch {
            print("[ReadingMetricsSyncService] Fetch stats cache failed: \(error)")
            return
        }

        let cache: ReadingStatsCache
        if let found = existing?.first {
            cache = found
        } else {
            cache = ReadingStatsCache(userId: userIdString)
            modelContext.insert(cache)
        }

        cache.totalReadingSeconds = stats.totalReadingSeconds
        cache.totalWordsRead = stats.totalWordsRead
        cache.lifetimeAvgWPM = stats.lifetimeAvgWpm ?? 0
        cache.daysRead = stats.daysRead
        cache.currentStreak = streak?.currentStreak ?? 0
        cache.longestStreak = streak?.longestStreak ?? 0
        cache.lastSyncedAt = Date()

        do {
            try modelContext.save()
        } catch {
            print("[ReadingMetricsSyncService] Save stats cache failed: \(error)")
        }
    }
}
