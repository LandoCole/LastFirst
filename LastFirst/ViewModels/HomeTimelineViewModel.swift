import Foundation

struct DayCuration: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let curation: Curation
    var items: [CurationItem]

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

struct CachedDayCuration: Codable {
    let id: UUID
    let date: Date
    let curation: Curation
    let items: [CurationItem]

    var asDayCuration: DayCuration {
        DayCuration(id: id, date: date, curation: curation, items: items)
    }

    init(day: DayCuration) {
        self.id = day.id
        self.date = day.date
        self.curation = day.curation
        self.items = day.items
    }
}

struct HomeTimelineCachePayload: Codable {
    let userId: UUID
    let savedAt: Date
    let days: [CachedDayCuration]
}

@MainActor
class HomeTimelineViewModel: ObservableObject {
    @Published var dayCurations: [DayCuration] = []
    @Published var filter = CurationFilter()
    @Published var isLoadingEarlier = false
    @Published var hasMoreEarlier = true
    @Published private(set) var hasResolvedInitialTimeline = false
    @Published private(set) var isUsingCachedBootstrap = false
    @Published private(set) var isGeneratingToday = false
    @Published private(set) var pendingTodayCurationId: UUID?

    private let userId: UUID
    private let pageSize = 7
    private let bootstrapCacheLimit = 3
    private let bootstrapCacheTTL: TimeInterval = 60 * 60 * 18

    var todayCurationId: UUID? {
        if let readyTodayId = dayCurations.last(where: \.isToday)?.id {
            return readyTodayId
        }
        if isGeneratingToday {
            return pendingTodayCurationId
        }
        return dayCurations.last?.id
    }

    var hasReadyTodayCuration: Bool {
        dayCurations.contains(where: \.isToday)
    }

    var earliestLoadedDayId: UUID? { dayCurations.first?.id }

    var shouldShowGeneratingTodayPage: Bool {
        isGeneratingToday && !hasReadyTodayCuration && pendingTodayCurationId != nil
    }

    init(userId: UUID) {
        self.userId = userId
    }

    func load() async {
        if !hasResolvedInitialTimeline {
            hydrateFromCacheIfNeeded()
        }

        do {
            async let readyCurations = SupabaseManager.shared.fetchDailyCurations(
                userId: userId,
                before: nil,
                limit: pageSize
            )
            async let pendingTodayCuration = SupabaseManager.shared.fetchTodaysPendingCuration(userId: userId)

            let curations = try await readyCurations
            let pendingToday = try await pendingTodayCuration

            let ids = curations.map(\.id)
            let itemsMap = try await SupabaseManager.shared.fetchCurationItemsBatch(curationIds: ids)

            let days = curations.map { curation in
                DayCuration(
                    id: curation.id,
                    date: curation.createdAt ?? Date(),
                    curation: curation,
                    items: itemsMap[curation.id] ?? []
                )
            }

            // curations come newest-first, reverse to oldest-first for timeline
            dayCurations = days.reversed()
            hasMoreEarlier = curations.count >= pageSize
            syncTodayState(with: pendingToday)
            hasResolvedInitialTimeline = true
            isUsingCachedBootstrap = false
            if dayCurations.isEmpty {
                UserDefaults.standard.removeObject(forKey: bootstrapCacheKey)
            } else {
                persistBootstrapCache(days: dayCurations)
            }
        } catch {
            hasResolvedInitialTimeline = true
            print("[HomeTimeline] Failed to load: \(error.localizedDescription)")
        }
    }

    func loadEarlier() async {
        guard !isLoadingEarlier, hasMoreEarlier else { return }
        guard let earliestDate = dayCurations.first?.date else { return }

        isLoadingEarlier = true
        defer { isLoadingEarlier = false }

        do {
            let curations = try await SupabaseManager.shared.fetchDailyCurations(
                userId: userId,
                before: earliestDate,
                limit: pageSize
            )
            guard !curations.isEmpty else {
                hasMoreEarlier = false
                return
            }

            let ids = curations.map(\.id)
            let itemsMap = try await SupabaseManager.shared.fetchCurationItemsBatch(curationIds: ids)

            let days = curations.map { curation in
                DayCuration(
                    id: curation.id,
                    date: curation.createdAt ?? Date(),
                    curation: curation,
                    items: itemsMap[curation.id] ?? []
                )
            }

            // Prepend older days (reversed to oldest-first)
            dayCurations.insert(contentsOf: days.reversed(), at: 0)
            hasMoreEarlier = curations.count >= pageSize
            persistBootstrapCache(days: dayCurations)
        } catch {
            print("[HomeTimeline] Failed to load earlier: \(error.localizedDescription)")
        }
    }

    func filteredItems(for day: DayCuration) -> [CurationItem] {
        guard filter.isActive else { return day.items }
        return day.items.filter { filter.matches($0) }
    }

    private func syncTodayState(with pendingToday: Curation?) {
        let shouldShowPendingToday = pendingToday?.status == "researching" && !hasReadyTodayCuration
        isGeneratingToday = shouldShowPendingToday
        pendingTodayCurationId = shouldShowPendingToday ? pendingToday?.id : nil
    }

    private var bootstrapCacheKey: String {
        "home_timeline_bootstrap_\(userId.uuidString)"
    }

    private func hydrateFromCacheIfNeeded() {
        guard dayCurations.isEmpty,
              let data = UserDefaults.standard.data(forKey: bootstrapCacheKey) else { return }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(HomeTimelineCachePayload.self, from: data),
              payload.userId == userId,
              Date().timeIntervalSince(payload.savedAt) <= bootstrapCacheTTL else {
            UserDefaults.standard.removeObject(forKey: bootstrapCacheKey)
            return
        }

        let calendar = Calendar.current
        if !calendar.isDate(payload.savedAt, inSameDayAs: Date()),
            let latestCachedDay = payload.days.max(by: { $0.date < $1.date }),
            !calendar.isDateInToday(latestCachedDay.date) {
            UserDefaults.standard.removeObject(forKey: bootstrapCacheKey)
            return
        }

        let cachedDays = payload.days
            .map(\.asDayCuration)
            .sorted { $0.date < $1.date }

        guard !cachedDays.isEmpty else { return }
        dayCurations = cachedDays
        isUsingCachedBootstrap = true
    }

    private func persistBootstrapCache(days: [DayCuration]) {
        let latestDays = Array(days.suffix(bootstrapCacheLimit))
        let payload = HomeTimelineCachePayload(
            userId: userId,
            savedAt: Date(),
            days: latestDays.map(CachedDayCuration.init(day:))
        )

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: bootstrapCacheKey)
    }
}
