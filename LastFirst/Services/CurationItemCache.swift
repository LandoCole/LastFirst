import Foundation

/// Caches curation items locally for offline access and instant loading.
/// Uses UserDefaults with per-curation keys and a 7-day TTL.
actor CurationItemCache {
    static let shared = CurationItemCache()

    private let ttl: TimeInterval = 60 * 60 * 24 * 7 // 7 days
    private let keyPrefix = "curation_items_cache_"

    func cache(items: [CurationItem], forCuration curationId: UUID) {
        let payload = CurationItemCachePayload(
            curationId: curationId,
            savedAt: Date(),
            items: items
        )
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: keyPrefix + curationId.uuidString)
    }

    func cachedItems(forCuration curationId: UUID) -> [CurationItem]? {
        guard let data = UserDefaults.standard.data(forKey: keyPrefix + curationId.uuidString) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(CurationItemCachePayload.self, from: data),
              Date().timeIntervalSince(payload.savedAt) <= ttl else {
            UserDefaults.standard.removeObject(forKey: keyPrefix + curationId.uuidString)
            return nil
        }
        return payload.items
    }

    func invalidate(curationId: UUID) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + curationId.uuidString)
    }
}

private struct CurationItemCachePayload: Codable {
    let curationId: UUID
    let savedAt: Date
    let items: [CurationItem]
}
