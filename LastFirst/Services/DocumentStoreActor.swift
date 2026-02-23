import Foundation

actor DocumentStoreActor {
    static let shared = DocumentStoreActor()

    enum StoreError: Error {
        case notFound
    }

    private let folderName = "canonical_documents_v1"
    private let manifestFileName = "manifest.json"
    private let renderFileName = "render_package.json"
    private let anchorsFileName = "text_anchors.json"

    func save(_ packages: CanonicalDocumentPackages) async throws {
        let documentId = packages.manifest.id
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let manifestURL = try fileURL(for: documentId, name: manifestFileName, createIfMissing: true)
        let renderURL = try fileURL(for: documentId, name: renderFileName, createIfMissing: true)
        let anchorsURL = try fileURL(for: documentId, name: anchorsFileName, createIfMissing: true)

        try encoder.encode(packages.manifest).write(to: manifestURL, options: [.atomic])
        try encoder.encode(packages.renderPackage).write(to: renderURL, options: [.atomic])
        try encoder.encode(packages.textAnchorsPackage).write(to: anchorsURL, options: [.atomic])
    }

    func load(documentId: UUID) async throws -> CanonicalDocumentPackages {
        let manifestURL = try fileURL(for: documentId, name: manifestFileName, createIfMissing: false)
        let renderURL = try fileURL(for: documentId, name: renderFileName, createIfMissing: false)
        let anchorsURL = try fileURL(for: documentId, name: anchorsFileName, createIfMissing: false)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw StoreError.notFound
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestData = try Data(contentsOf: manifestURL)
        let renderData = try Data(contentsOf: renderURL)
        let anchorsData = try Data(contentsOf: anchorsURL)

        let manifest = try decoder.decode(DocumentManifest.self, from: manifestData)
        let renderPackage = try decoder.decode(RenderPackage.self, from: renderData)
        let textAnchors = try decoder.decode(TextAnchorsPackage.self, from: anchorsData)

        return CanonicalDocumentPackages(
            manifest: manifest,
            renderPackage: renderPackage,
            textAnchorsPackage: textAnchors
        )
    }

    func delete(documentId: UUID) async throws {
        let dir = try directoryURL(for: documentId, createIfMissing: false)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func fileURL(for documentId: UUID, name: String, createIfMissing: Bool) throws -> URL {
        let dir = try directoryURL(for: documentId, createIfMissing: createIfMissing)
        return dir.appendingPathComponent(name)
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
