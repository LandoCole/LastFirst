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

@MainActor
class HomeTimelineViewModel: ObservableObject {
    @Published var dayCurations: [DayCuration] = []
    @Published var filter = CurationFilter()
    @Published var isLoadingEarlier = false
    @Published var hasMoreEarlier = true

    private let userId: UUID
    private let pageSize = 7

    var todayCurationId: UUID? { dayCurations.last?.id }

    init(userId: UUID) {
        self.userId = userId
    }

    func load() async {
        do {
            let curations = try await SupabaseManager.shared.fetchDailyCurations(
                userId: userId,
                before: nil,
                limit: pageSize
            )
            guard !curations.isEmpty else { return }

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
        } catch {
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
        } catch {
            print("[HomeTimeline] Failed to load earlier: \(error.localizedDescription)")
        }
    }

    func filteredItems(for day: DayCuration) -> [CurationItem] {
        guard filter.isActive else { return day.items }
        return day.items.filter { filter.matches($0) }
    }
}
