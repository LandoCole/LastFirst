import UIKit

@MainActor
final class CurationCardColorCache {
    static let shared = CurationCardColorCache()

    private static let maxCacheSize = 100
    private var cache: [String: UIColor] = [:]
    private var accessOrder: [String] = []
    private var inFlight: [String: Task<UIColor?, Never>] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearCache()
            }
        }
    }

    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        inFlight.removeAll()
    }

    func dominantColor(for urlString: String) async -> UIColor? {
        if let cached = cache[urlString] { return cached }

        if let existing = inFlight[urlString] {
            return await existing.value
        }

        let task = Task<UIColor?, Never> {
            guard let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  let color = image.dominantColor() else {
                return nil
            }
            return color
        }

        inFlight[urlString] = task
        let result = await task.value
        inFlight[urlString] = nil

        if let result {
            cache[urlString] = result
            accessOrder.append(urlString)
            // LRU eviction
            while cache.count > Self.maxCacheSize, let oldest = accessOrder.first {
                accessOrder.removeFirst()
                cache.removeValue(forKey: oldest)
            }
        }
        return result
    }
}
