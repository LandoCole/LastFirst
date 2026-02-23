import Foundation

final class DocumentIngestionService: @unchecked Sendable {
    static let currentIngestionVersion: Int = 5

    enum IngestionError: Error {
        case unsupportedSource
        case emptyContent
    }

    func ingestLocalFile(url: URL, fileType: DocumentSource.LocalFileType, documentId: UUID) async throws -> ReaderDocument {
        let source = DocumentSource.localFile(.init(url: url, fileType: fileType))

        let packages = try await ingestCanonicalPackages(source: source, documentId: documentId)
        if packages.textAnchorsPackage.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw IngestionError.emptyContent
        }
        return CanonicalDocumentAdapter.buildReaderDocument(
            from: packages,
            source: source,
            ingestionVersion: Self.currentIngestionVersion
        )
    }

    func ingestCanonicalPackages(source: DocumentSource, documentId: UUID) async throws -> CanonicalDocumentPackages {
        await CanonicalParsingService.shared.configureCoordinatorIfNeeded()

        do {
            return try await DocumentStoreActor.shared.load(documentId: documentId)
        } catch let error as DocumentStoreActor.StoreError {
            switch error {
            case .notFound:
                break
            }
        }

        let request = ParsingCoordinatorActor.ParseRequest(documentId: documentId, source: source)
        return try await ParsingCoordinatorActor.shared.enqueue(request)
    }

}
