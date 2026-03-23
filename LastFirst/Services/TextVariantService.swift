import Foundation

actor TextVariantService {
    static let shared = TextVariantService()

    private let store: TextVariantStoreActor
    private let maxBatchCharacters = 40_000
    private let maxBatchSegments = 40

    private var activeTask: Task<TextVariant, Never>?

    var isProcessing: Bool { activeTask != nil }

    init(store: TextVariantStoreActor = .shared) {
        self.store = store
    }

    // MARK: - Public API

    func createVariant(
        documentId: UUID,
        unitID: String,
        kind: TextVariantKind,
        name: String,
        instructions: String?,
        conciseness: SummaryConciseness?,
        canonicalPackages: CanonicalDocumentPackages,
        source: DocumentSource
    ) async -> TextVariant {
        activeTask?.cancel()

        var variant = TextVariant(
            documentId: documentId,
            unitID: unitID,
            name: name,
            kind: kind,
            instructions: instructions,
            status: .processing
        )

        let task = Task<TextVariant, Never> { [weak self] in
            guard let self else { return variant }

            switch kind {
            case .speedClean:
                variant = await self.runSpeedClean(
                    variant: variant,
                    documentId: documentId,
                    unitID: unitID,
                    canonicalPackages: canonicalPackages,
                    source: source
                )

            case .summary:
                variant = await self.runTransform(
                    variant: variant,
                    mode: "summarize",
                    conciseness: conciseness?.rawValue ?? "moderate",
                    instructions: nil,
                    unitID: unitID,
                    canonicalPackages: canonicalPackages
                )

            case .custom:
                variant = await self.runTransform(
                    variant: variant,
                    mode: "custom",
                    conciseness: nil,
                    instructions: instructions,
                    unitID: unitID,
                    canonicalPackages: canonicalPackages
                )

            case .audio:
                variant.status = .queued
            }

            await self.persistVariant(variant, documentId: documentId)

            // Fire-and-forget sync to Supabase
            if let userId = await MainActor.run(body: {
                SupabaseManager.shared.client?.auth.currentSession?.user.id
            }) {
                let variantCopy = variant
                Task.detached {
                    await TextVariantSyncService.shared.syncToRemote(variant: variantCopy, userId: userId)
                }
            }

            return variant
        }

        activeTask = task
        let result = await task.value
        activeTask = nil
        return result
    }

    func loadVariants(documentId: UUID) async -> TextVariantPackage? {
        if let local = try? await store.load(documentId: documentId) {
            return local
        }

        // Fallback: try loading from remote
        guard let userId = await MainActor.run(body: {
            SupabaseManager.shared.client?.auth.currentSession?.user.id
        }) else { return nil }

        guard let remoteVariants = await TextVariantSyncService.shared.fetchFromRemote(
            documentId: documentId, userId: userId
        ), !remoteVariants.isEmpty else { return nil }

        let package = TextVariantPackage(documentId: documentId, variants: remoteVariants)
        try? await store.save(package)
        return package
    }

    func deleteVariant(id: UUID, documentId: UUID) async {
        guard var package = try? await store.load(documentId: documentId) else { return }
        package.variants.removeAll { $0.id == id }
        package.updatedAt = Date()
        try? await store.save(package)
    }

    func apply(variant: TextVariant, to canonicalPackages: CanonicalDocumentPackages) -> CanonicalDocumentPackages {
        let chunkBySegmentID = Dictionary(
            uniqueKeysWithValues: variant.chunks
                .filter { $0.status == .ready }
                .map { ($0.segmentID, $0) }
        )

        var segments = canonicalPackages.textAnchorsPackage.segments.sorted { $0.order < $1.order }
        var plainText = ""

        for index in segments.indices {
            let isTargetUnit = segments[index].unitID == variant.unitID
            let replacement: String
            if isTargetUnit, let chunk = chunkBySegmentID[segments[index].id] {
                replacement = chunk.transformedText
            } else {
                replacement = segments[index].text
            }
            let text = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            let start = plainText.count
            plainText += text
            let end = plainText.count
            segments[index].text = text
            segments[index].textRange = TextRange(start: start, end: end)
            if index < segments.count - 1 {
                plainText += "\n\n"
            }
        }

        var textAnchors = canonicalPackages.textAnchorsPackage
        textAnchors.segments = segments
        textAnchors.plainText = plainText

        return CanonicalDocumentPackages(
            manifest: canonicalPackages.manifest,
            renderPackage: canonicalPackages.renderPackage,
            textAnchorsPackage: textAnchors
        )
    }

    // MARK: - Speed Clean Delegation

    private func runSpeedClean(
        variant: TextVariant,
        documentId: UUID,
        unitID: String,
        canonicalPackages: CanonicalDocumentPackages,
        source: DocumentSource
    ) async -> TextVariant {
        var result = variant

        let prepared = await SpeedCleanService.shared.polishUnit(
            documentId: documentId,
            source: source,
            canonicalPackages: canonicalPackages,
            unitID: unitID
        )

        let speedCleanChunks = prepared.speedCleanPackage.chunks.filter { $0.unitID == unitID }
        result.chunks = speedCleanChunks.map { chunk in
            TextVariantChunk(
                segmentID: chunk.segmentID,
                unitID: chunk.unitID,
                transformedText: chunk.cleanedText,
                status: chunk.status == .ready ? .ready : .failed
            )
        }
        result.status = result.chunks.allSatisfy({ $0.status == .ready }) ? .ready : .failed
        result.updatedAt = Date()
        return result
    }

    // MARK: - Server Transform (Summarize / Custom)

    private func runTransform(
        variant: TextVariant,
        mode: String,
        conciseness: String?,
        instructions: String?,
        unitID: String,
        canonicalPackages: CanonicalDocumentPackages
    ) async -> TextVariant {
        var result = variant

        let rawSegments = canonicalPackages.textAnchorsPackage.segments
            .filter { $0.unitID == unitID }
            .sorted { $0.order < $1.order }

        guard !rawSegments.isEmpty else {
            result.status = .failed
            result.updatedAt = Date()
            return result
        }

        let unitTitle = canonicalPackages.textAnchorsPackage.units.first { $0.id == unitID }?.title
        let batches = buildBatches(rawSegments)
        var allChunks: [TextVariantChunk] = []

        for batch in batches {
            guard !Task.isCancelled else {
                result.status = .failed
                result.updatedAt = Date()
                return result
            }

            let inputs = batch.map {
                SupabaseManager.TextTransformSegmentInput(id: $0.id, text: $0.text)
            }

            do {
                let serverResults = try await SupabaseManager.shared.textTransform(
                    mode: mode,
                    conciseness: conciseness,
                    instructions: instructions,
                    unitID: unitID,
                    unitTitle: unitTitle,
                    segments: inputs
                )

                let resultMap = Dictionary(
                    uniqueKeysWithValues: serverResults.map { ($0.segmentID, $0.transformedText) }
                )

                for segment in batch {
                    let transformedText = resultMap[segment.id] ?? segment.text
                    allChunks.append(TextVariantChunk(
                        segmentID: segment.id,
                        unitID: unitID,
                        transformedText: transformedText,
                        status: .ready
                    ))
                }
            } catch {
                print("[TextVariantService] Batch transform failed: \(error.localizedDescription)")
                for segment in batch {
                    allChunks.append(TextVariantChunk(
                        segmentID: segment.id,
                        unitID: unitID,
                        transformedText: segment.text,
                        status: .failed
                    ))
                }
            }
        }

        result.chunks = allChunks
        result.status = allChunks.allSatisfy({ $0.status == .ready }) ? .ready : .failed
        result.updatedAt = Date()
        return result
    }

    // MARK: - Batching

    private func buildBatches(_ segments: [ContentSegment]) -> [[ContentSegment]] {
        var batches: [[ContentSegment]] = []
        var currentBatch: [ContentSegment] = []
        var currentChars = 0

        for segment in segments {
            if !currentBatch.isEmpty &&
                (currentBatch.count >= maxBatchSegments || currentChars + segment.text.count > maxBatchCharacters) {
                batches.append(currentBatch)
                currentBatch = []
                currentChars = 0
            }
            currentBatch.append(segment)
            currentChars += segment.text.count
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    // MARK: - Persistence

    private func persistVariant(_ variant: TextVariant, documentId: UUID) async {
        var package: TextVariantPackage
        if let existing = try? await store.load(documentId: documentId) {
            package = existing
        } else {
            package = TextVariantPackage(documentId: documentId)
        }

        if let index = package.variants.firstIndex(where: { $0.id == variant.id }) {
            package.variants[index] = variant
        } else {
            package.variants.append(variant)
        }
        package.updatedAt = Date()

        try? await store.save(package)
    }
}
