import Foundation
import UniformTypeIdentifiers

actor ResourceCacheActor {
    static let shared = ResourceCacheActor()

    enum CacheError: Error {
        case notFound
        case invalidURL
    }

    private let folderName = "render_resources_v1"

    func store(data: Data, documentId: UUID, relativePath: String) async throws -> URL {
        let fileURL = try fileURL(for: documentId, relativePath: relativePath, createIfMissing: true)
        let folderURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    func storeFile(at url: URL, documentId: UUID, relativePath: String) async throws -> URL {
        let fileURL = try fileURL(for: documentId, relativePath: relativePath, createIfMissing: true)
        let folderURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.copyItem(at: url, to: fileURL)
        return fileURL
    }

    func data(documentId: UUID, relativePath: String) async throws -> Data {
        let fileURL = try fileURL(for: documentId, relativePath: relativePath, createIfMissing: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CacheError.notFound
        }
        return try Data(contentsOf: fileURL)
    }

    func resolve(url: URL) async throws -> (data: Data, mimeType: String) {
        guard let host = url.host, let documentId = UUID(uuidString: host) else {
            throw CacheError.invalidURL
        }

        let resolvedPath = normalizedPath(from: url.path)
        let relativePath = resolvedPath.isEmpty ? "index.html" : resolvedPath
        let fileURL = try fileURL(for: documentId, relativePath: relativePath, createIfMissing: false)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CacheError.notFound
        }

        let data = try Data(contentsOf: fileURL)
        return (data: data, mimeType: mimeType(for: fileURL))
    }

    func delete(documentId: UUID) async throws {
        let dir = try directoryURL(for: documentId, createIfMissing: false)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    func clear() async throws {
        let base = try baseDirectoryURL(createIfMissing: false)
        if FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.removeItem(at: base)
        }
    }

    private func fileURL(for documentId: UUID, relativePath: String, createIfMissing: Bool) throws -> URL {
        let dir = try directoryURL(for: documentId, createIfMissing: createIfMissing)
        let normalized = normalizedPath(from: relativePath)
        return dir.appendingPathComponent(normalized)
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

    private func normalizedPath(from rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let components = decoded.split(separator: "/").filter { $0 != ".." && $0 != "." }
        return components.joined(separator: "/")
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "html": return "text/html"
        case "htm": return "text/html"
        case "xhtml": return "application/xhtml+xml"
        case "css": return "text/css"
        case "js": return "text/javascript"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "pdf": return "application/pdf"
        default:
            if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }
    }
}
