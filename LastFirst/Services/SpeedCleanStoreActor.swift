import Foundation

actor SpeedCleanStoreActor {
    static let shared = SpeedCleanStoreActor()

    enum StoreError: Error {
        case notFound
    }

    private let folderName = "speed_clean_v1"
    private let packageFileName = "speed_clean.json"

    func save(_ package: SpeedCleanPackage) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let url = try fileURL(for: package.documentId, createIfMissing: true)
        try encoder.encode(package).write(to: url, options: [.atomic])
    }

    func load(documentId: UUID) async throws -> SpeedCleanPackage {
        let url = try fileURL(for: documentId, createIfMissing: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.notFound
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        return try decoder.decode(SpeedCleanPackage.self, from: data)
    }

    func delete(documentId: UUID) async throws {
        let dir = try directoryURL(for: documentId, createIfMissing: false)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func fileURL(for documentId: UUID, createIfMissing: Bool) throws -> URL {
        let dir = try directoryURL(for: documentId, createIfMissing: createIfMissing)
        return dir.appendingPathComponent(packageFileName)
    }

    private func directoryURL(for documentId: UUID, createIfMissing: Bool) throws -> URL {
        let base = try baseDirectoryURL(createIfMissing: createIfMissing)
        let dir = base.appendingPathComponent(documentId.uuidString, isDirectory: true)
        if createIfMissing && !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func baseDirectoryURL(createIfMissing: Bool) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if createIfMissing && !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
