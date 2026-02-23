import Foundation

actor ParsingCoordinatorActor {
    static let shared = ParsingCoordinatorActor()

    enum CoordinatorError: Error {
        case notImplemented
    }

    struct ParseRequest: Sendable {
        var documentId: UUID
        var source: DocumentSource

        init(documentId: UUID, source: DocumentSource) {
            self.documentId = documentId
            self.source = source
        }
    }

    typealias ParseHandler = @Sendable (ParseRequest) async throws -> CanonicalDocumentPackages

    private var activeTasks: [UUID: Task<CanonicalDocumentPackages, Error>] = [:]
    private var handler: ParseHandler?

    func setHandler(_ handler: @escaping ParseHandler) {
        self.handler = handler
    }

    func enqueue(_ request: ParseRequest) async throws -> CanonicalDocumentPackages {
        if let existing = activeTasks[request.documentId] {
            return try await existing.value
        }

        let currentHandler = handler
        let task = Task {
            guard let currentHandler else {
                throw CoordinatorError.notImplemented
            }
            return try await currentHandler(request)
        }

        activeTasks[request.documentId] = task
        defer { activeTasks.removeValue(forKey: request.documentId) }

        return try await task.value
    }

    func cancel(documentId: UUID) {
        activeTasks[documentId]?.cancel()
        activeTasks.removeValue(forKey: documentId)
    }
}
