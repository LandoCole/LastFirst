import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum SpeedCleanProgressEvent: Sendable {
    case heuristicCleaning(batchIndex: Int, totalBatches: Int)
    case onDevicePolishing(batchIndex: Int, totalBatches: Int)
    case serverFallback(batchIndex: Int, totalBatches: Int)
}

protocol SpeedCleanProgressSink: Actor {
    func report(_ event: SpeedCleanProgressEvent) async
}

actor SpeedCleanService {
    static let shared = SpeedCleanService()

    struct PreparedResult: Sendable {
        var packages: CanonicalDocumentPackages
        var speedCleanPackage: SpeedCleanPackage
    }

    struct DebugOptions: Sendable {
        var profile: SpeedCleanProfile
        var structuralKind: StructuralContentKind?
        var allowOnDeviceModel: Bool
        var allowServerFallback: Bool
        var unitTitle: String?

        init(
            profile: SpeedCleanProfile = .article,
            structuralKind: StructuralContentKind? = .paragraph,
            allowOnDeviceModel: Bool = true,
            allowServerFallback: Bool = true,
            unitTitle: String? = "Debug Sample"
        ) {
            self.profile = profile
            self.structuralKind = structuralKind
            self.allowOnDeviceModel = allowOnDeviceModel
            self.allowServerFallback = allowServerFallback
            self.unitTitle = unitTitle
        }
    }

    enum DebugMethod: String, CaseIterable, Identifiable, Sendable {
        case local
        case onDeviceModel
        case serverFallback
        case localAfterOnDeviceFailure
        case localAfterServerFailure
        case localAfterOnDeviceAndServerFailure

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .local:
                return "Local"
            case .onDeviceModel:
                return "On-device"
            case .serverFallback:
                return "Server"
            case .localAfterOnDeviceFailure:
                return "Local after on-device failure"
            case .localAfterServerFailure:
                return "Local after server failure"
            case .localAfterOnDeviceAndServerFailure:
                return "Local after on-device + server failure"
            }
        }

        var usesFallback: Bool {
            switch self {
            case .local, .onDeviceModel, .serverFallback:
                return false
            case .localAfterOnDeviceFailure, .localAfterServerFailure, .localAfterOnDeviceAndServerFailure:
                return true
            }
        }
    }

    struct DebugSegmentResult: Identifiable, Sendable {
        var id: String { segmentID }
        var segmentID: String
        var originalText: String
        var cleanedText: String
        var method: DebugMethod
        var deliveryMode: SpeedCleanDeliveryMode
        var attemptedOnDeviceModel: Bool
        var attemptedServerFallback: Bool
        var errors: [String]
        var logs: [String]
    }

    struct DebugRunResult: Sendable {
        var cleanedText: String
        var segmentResults: [DebugSegmentResult]
        var deliveryMode: SpeedCleanDeliveryMode
        var logs: [String]
        var lastError: String?

        var usedFallback: Bool {
            segmentResults.contains { $0.method.usesFallback }
        }
    }

    private struct SegmentCleanResult: Sendable {
        var segmentID: String
        var cleanedText: String
        var deliveryMode: SpeedCleanDeliveryMode
        var debugMethod: DebugMethod
        var attemptedOnDeviceModel: Bool
        var attemptedServerFallback: Bool
        var errors: [String]
        var logs: [String]
    }

    private struct BatchCleanOutput: Sendable {
        var results: [SegmentCleanResult]
        var logs: [String]
    }

    private struct ModelAttemptResult: Sendable {
        var results: [SegmentCleanResult]?
        var attempted: Bool
        var logs: [String]
        var errorMessage: String?
    }

    private struct CleanExecutionOptions: Sendable {
        var allowOnDeviceModel: Bool = true
        var allowServerFallback: Bool = true
    }

    private enum CleaningStrategy: String, Sendable {
        case foundationModelsPrimary   // FM → Server → Local heuristic
        case serverPrimary             // Server → Local heuristic
    }

    private struct ModelPromptPayload: Encodable {
        var profile: String
        var unitID: String
        var unitTitle: String?
        var segments: [ModelPromptSegment]

        enum CodingKeys: String, CodingKey {
            case profile, segments
            case unitID = "unit_id"
            case unitTitle = "unit_title"
        }
    }

    private struct ModelPromptSegment: Encodable {
        var segmentID: String
        var text: String
        var structuralKind: String?

        enum CodingKeys: String, CodingKey {
            case text
            case segmentID = "segment_id"
            case structuralKind = "structural_kind"
        }
    }

    private struct ModelResponsePayload: Decodable {
        var segments: [ModelResponseSegment]
    }

    private struct ModelResponseSegment: Decodable {
        var segmentID: String
        var cleanedText: String

        enum CodingKeys: String, CodingKey {
            case segmentID = "segment_id"
            case cleanedText = "cleaned_text"
        }
    }

    private struct ArtifactDescriptor {
        var kindTitle: String
        var label: String?
        var descriptor: String?

        var reference: String {
            [kindTitle, label, descriptor]
                .compactMap { value in
                    guard let value else { return nil }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                .joined(separator: " ")
        }

        var kindNoun: String {
            kindTitle.lowercased()
        }
    }

    private let store: SpeedCleanStoreActor
    private var backgroundTasks: [UUID: Task<Void, Never>] = [:]
    private let maxBatchCharacters = 40_000
    private let maxBatchSegments = 40
    private let serverFallbackModel = "gpt-4.1"

    /// Circuit breaker: after a server failure (e.g. 401), disable server
    /// fallback for this duration to avoid spamming the edge function.
    private var serverFallbackDisabledUntil: Date?

    private static let cleaningStrategyKey = "speed_clean_strategy"
    private var resolvedStrategy: CleaningStrategy?

    private func resolveCleaningStrategy() -> CleaningStrategy {
        if let cached = resolvedStrategy { return cached }
        let strategy = probeFoundationModelsAvailability()
        resolvedStrategy = strategy
        UserDefaults.standard.set(strategy.rawValue, forKey: Self.cleaningStrategyKey)
        return strategy
    }

    private func probeFoundationModelsAvailability() -> CleaningStrategy {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return .foundationModelsPrimary
            }
        }
        #endif
        return .serverPrimary
    }

    private enum ServerCleanupSkipReason {
        case unavailableClient
        case unauthenticatedSession
        case batchTooLarge
        case circuitBreakerOpen

        var message: String {
            switch self {
            case .unavailableClient:
                return "Server fallback skipped because the Supabase client is unavailable."
            case .unauthenticatedSession:
                return "Server fallback skipped because no signed-in Supabase session is available."
            case .batchTooLarge:
                return "Server fallback skipped because the batch exceeds the size limit."
            case .circuitBreakerOpen:
                return "Server fallback skipped because a previous server call failed recently."
            }
        }
    }

    init(store: SpeedCleanStoreActor = .shared) {
        self.store = store
    }

    func preparedPackages(
        documentId: UUID,
        source: DocumentSource,
        canonicalPackages: CanonicalDocumentPackages,
        priorityUnitID: String?,
        progressSink: (any SpeedCleanProgressSink)? = nil
    ) async -> PreparedResult {
        var package = await loadOrCreatePackage(documentId: documentId, source: source, canonicalPackages: canonicalPackages)
        let synchronousUnits = synchronousUnitIDs(
            for: package.profile,
            priorityUnitID: priorityUnitID,
            canonicalPackages: canonicalPackages
        )

        if needsCleaning(unitIDs: synchronousUnits, package: package, canonicalPackages: canonicalPackages) {
            package = await clean(
                unitIDs: synchronousUnits,
                canonicalPackages: canonicalPackages,
                package: package,
                progressSink: progressSink
            )
            try? await store.save(package)
        }

        scheduleBackgroundCleaning(documentId: documentId, source: source, canonicalPackages: canonicalPackages)
        return PreparedResult(packages: apply(package: package, to: canonicalPackages), speedCleanPackage: package)
    }

    func polishUnit(
        documentId: UUID,
        source: DocumentSource,
        canonicalPackages: CanonicalDocumentPackages,
        unitID: String,
        progressSink: (any SpeedCleanProgressSink)? = nil
    ) async -> PreparedResult {
        var package = await loadOrCreatePackage(documentId: documentId, source: source, canonicalPackages: canonicalPackages)
        package = await clean(
            unitIDs: [unitID],
            canonicalPackages: canonicalPackages,
            package: package,
            progressSink: progressSink
        )
        try? await store.save(package)
        scheduleBackgroundCleaning(documentId: documentId, source: source, canonicalPackages: canonicalPackages)
        return PreparedResult(packages: apply(package: package, to: canonicalPackages), speedCleanPackage: package)
    }

    func latestPackage(
        documentId: UUID,
        source: DocumentSource,
        canonicalPackages: CanonicalDocumentPackages
    ) async -> SpeedCleanPackage {
        await loadOrCreatePackage(documentId: documentId, source: source, canonicalPackages: canonicalPackages)
    }

    func debugCleanText(
        _ text: String,
        options: DebugOptions = DebugOptions()
    ) async -> DebugRunResult {
        let segments = debugSegments(from: text, structuralKind: options.structuralKind)
        guard !segments.isEmpty else {
            let log = makeLogLine("Debug Speed Clean run skipped because the input text was empty.")
            return DebugRunResult(
                cleanedText: "",
                segmentResults: [],
                deliveryMode: .onDevice,
                logs: [log],
                lastError: nil
            )
        }

        let repeatedNoiseKeys = repeatedNoiseLineKeys(in: segments)
        let batches = segmentBatches(for: segments)
        let executionOptions = CleanExecutionOptions(
            allowOnDeviceModel: options.allowOnDeviceModel,
            allowServerFallback: options.allowServerFallback
        )

        var allResults: [SegmentCleanResult] = []
        var allLogs: [String] = [
            makeLogLine(
                "Starting debug Speed Clean run with \(segments.count) segment(s), profile=\(options.profile.rawValue), structuralKind=\(options.structuralKind?.rawValue ?? "nil"), allowOnDevice=\(options.allowOnDeviceModel), allowServer=\(options.allowServerFallback)."
            )
        ]

        for (batchIndex, batch) in batches.enumerated() {
            let output = await cleanBatch(
                segments: batch,
                unitID: "debug-unit",
                unitTitle: options.unitTitle,
                profile: options.profile,
                repeatedNoiseLineKeys: repeatedNoiseKeys,
                batchIndex: batchIndex,
                totalBatches: batches.count,
                progressSink: nil,
                executionOptions: executionOptions
            )
            allResults.append(contentsOf: output.results)
            allLogs.append(contentsOf: output.logs)
        }

        let resultsBySegmentID = Dictionary(uniqueKeysWithValues: allResults.map { ($0.segmentID, $0) })
        let segmentResults = segments.map { segment in
            let result = resultsBySegmentID[segment.id] ?? SegmentCleanResult(
                segmentID: segment.id,
                cleanedText: cleanSegmentText(
                    segment,
                    profile: options.profile,
                    repeatedNoiseLineKeys: repeatedNoiseKeys
                ),
                deliveryMode: .onDevice,
                debugMethod: .local,
                attemptedOnDeviceModel: false,
                attemptedServerFallback: false,
                errors: [],
                logs: allLogs
            )

            return DebugSegmentResult(
                segmentID: segment.id,
                originalText: segment.text,
                cleanedText: result.cleanedText,
                method: result.debugMethod,
                deliveryMode: result.deliveryMode,
                attemptedOnDeviceModel: result.attemptedOnDeviceModel,
                attemptedServerFallback: result.attemptedServerFallback,
                errors: result.errors,
                logs: result.logs.isEmpty ? allLogs : result.logs
            )
        }

        let cleanedText = segmentResults
            .map(\.cleanedText)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return DebugRunResult(
            cleanedText: cleanedText,
            segmentResults: segmentResults,
            deliveryMode: overallDeliveryMode(for: allResults),
            logs: allLogs,
            lastError: segmentResults.flatMap(\.errors).last
        )
    }

    func isUnitReady(
        documentId: UUID,
        source: DocumentSource,
        canonicalPackages: CanonicalDocumentPackages,
        unitID: String
    ) async -> Bool {
        let package = await loadOrCreatePackage(documentId: documentId, source: source, canonicalPackages: canonicalPackages)
        let segmentIDs = canonicalPackages.textAnchorsPackage.segments
            .filter { $0.unitID == unitID }
            .map(\.id)
        return package.isUnitReady(unitID, segmentIDs: segmentIDs)
    }

    private func loadOrCreatePackage(
        documentId: UUID,
        source: DocumentSource,
        canonicalPackages: CanonicalDocumentPackages
    ) async -> SpeedCleanPackage {
        if let existing = try? await store.load(documentId: documentId) {
            return existing
        }

        let created = makePackage(documentId: documentId, source: source, canonicalPackages: canonicalPackages)
        try? await store.save(created)
        return created
    }

    private func makePackage(
        documentId: UUID,
        source: DocumentSource,
        canonicalPackages: CanonicalDocumentPackages
    ) -> SpeedCleanPackage {
        let profile = profile(for: source)
        let chunks = canonicalPackages.textAnchorsPackage.segments.map {
            SpeedCleanChunk(segmentID: $0.id, unitID: $0.unitID, cleanedText: "", status: .notStarted)
        }
        return SpeedCleanPackage(documentId: documentId, profile: profile, chunks: chunks)
    }

    private func profile(for source: DocumentSource) -> SpeedCleanProfile {
        switch source {
        case .localFile(let local):
            switch local.fileType {
            case .epub:
                return .book
            case .pdf:
                return .pdfPaper
            }
        case .web:
            return .article
        }
    }

    private func synchronousUnitIDs(
        for profile: SpeedCleanProfile,
        priorityUnitID: String?,
        canonicalPackages: CanonicalDocumentPackages
    ) -> [String] {
        let unitIDs = canonicalPackages.textAnchorsPackage.units
            .sorted { $0.order < $1.order }
            .map(\.id)

        switch profile {
        case .article:
            return unitIDs
        case .book, .pdfPaper:
            if let priorityUnitID, unitIDs.contains(priorityUnitID) {
                return [priorityUnitID]
            }
            if let first = unitIDs.first {
                return [first]
            }
            return []
        }
    }

    private func pendingUnitIDs(
        package: SpeedCleanPackage,
        canonicalPackages: CanonicalDocumentPackages
    ) -> [String] {
        canonicalPackages.textAnchorsPackage.units
            .sorted { $0.order < $1.order }
            .map(\.id)
            .filter { unitID in
                let segmentIDs = canonicalPackages.textAnchorsPackage.segments
                    .filter { $0.unitID == unitID }
                    .map(\.id)
                return !package.isUnitReady(unitID, segmentIDs: segmentIDs)
            }
    }

    private func needsCleaning(
        unitIDs: [String],
        package: SpeedCleanPackage,
        canonicalPackages: CanonicalDocumentPackages
    ) -> Bool {
        guard !unitIDs.isEmpty else { return false }
        let targetUnitIDs = Set(unitIDs)
        let segmentIDs = canonicalPackages.textAnchorsPackage.segments
            .filter { targetUnitIDs.contains($0.unitID) }
            .map(\.id)
        for segmentID in segmentIDs {
            guard let chunk = package.chunk(for: segmentID) else { return true }
            if chunk.status != .ready {
                return true
            }
        }
        return false
    }

    private func scheduleBackgroundCleaning(
        documentId: UUID,
        source: DocumentSource,
        canonicalPackages: CanonicalDocumentPackages
    ) {
        if let existing = backgroundTasks[documentId], !existing.isCancelled {
            return
        }

        backgroundTasks[documentId] = Task {
            await self.processBackgroundCleaning(
                documentId: documentId,
                source: source,
                canonicalPackages: canonicalPackages
            )
        }
    }

    private func processBackgroundCleaning(
        documentId: UUID,
        source: DocumentSource,
        canonicalPackages: CanonicalDocumentPackages
    ) async {
        var package = await loadOrCreatePackage(documentId: documentId, source: source, canonicalPackages: canonicalPackages)
        let units = pendingUnitIDs(package: package, canonicalPackages: canonicalPackages)

        for unitID in units {
            if Task.isCancelled {
                break
            }
            package = await clean(unitIDs: [unitID], canonicalPackages: canonicalPackages, package: package)
            try? await store.save(package)
            await Task.yield()
        }

        backgroundTasks[documentId] = nil
    }

    private func clean(
        unitIDs: [String],
        canonicalPackages: CanonicalDocumentPackages,
        package: SpeedCleanPackage,
        progressSink: (any SpeedCleanProgressSink)? = nil
    ) async -> SpeedCleanPackage {
        guard !unitIDs.isEmpty else { return package }

        let repeatedNoiseLineKeys = repeatedNoiseLineKeys(in: canonicalPackages)
        let segmentsByUnit = Dictionary(grouping: canonicalPackages.textAnchorsPackage.segments, by: \.unitID)
        let unitTitles = Dictionary(uniqueKeysWithValues: canonicalPackages.textAnchorsPackage.units.map { ($0.id, $0.title) })
        let updatedAt = Date()
        var updatedPackage = package

        for unitID in unitIDs {
            guard let segments = segmentsByUnit[unitID]?.sorted(by: { $0.order < $1.order }), !segments.isEmpty else {
                continue
            }

            let batches = segmentBatches(for: segments)
            for (batchIndex, batch) in batches.enumerated() {
                let output = await cleanBatch(
                    segments: batch,
                    unitID: unitID,
                    unitTitle: unitTitles[unitID],
                    profile: package.profile,
                    repeatedNoiseLineKeys: repeatedNoiseLineKeys,
                    batchIndex: batchIndex,
                    totalBatches: batches.count,
                    progressSink: progressSink
                )

                let resultMap = Dictionary(uniqueKeysWithValues: output.results.map { ($0.segmentID, $0) })
                updatedPackage.chunks = updatedPackage.chunks.map { chunk in
                    guard let result = resultMap[chunk.segmentID] else {
                        return chunk
                    }

                    return SpeedCleanChunk(
                        segmentID: chunk.segmentID,
                        unitID: chunk.unitID,
                        cleanedText: result.cleanedText,
                        status: .ready,
                        deliveryMode: result.deliveryMode,
                        updatedAt: updatedAt
                    )
                }
            }
        }

        updatedPackage.deliveryMode = overallDeliveryMode(for: updatedPackage)
        updatedPackage.status = overallStatus(for: updatedPackage)
        updatedPackage.updatedAt = updatedAt
        return updatedPackage
    }

    private func segmentBatches(for segments: [ContentSegment]) -> [[ContentSegment]] {
        guard !segments.isEmpty else { return [] }

        var batches: [[ContentSegment]] = []
        var currentBatch: [ContentSegment] = []
        var currentCharacters = 0

        for segment in segments {
            let segmentCharacters = max(segment.text.count, 1)
            let exceedsBatch = !currentBatch.isEmpty && (
                currentBatch.count >= maxBatchSegments ||
                currentCharacters + segmentCharacters > maxBatchCharacters
            )

            if exceedsBatch {
                batches.append(currentBatch)
                currentBatch = []
                currentCharacters = 0
            }

            currentBatch.append(segment)
            currentCharacters += segmentCharacters
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    private func cleanBatch(
        segments: [ContentSegment],
        unitID: String,
        unitTitle: String?,
        profile: SpeedCleanProfile,
        repeatedNoiseLineKeys: Set<String>,
        batchIndex: Int,
        totalBatches: Int,
        progressSink: (any SpeedCleanProgressSink)?,
        executionOptions: CleanExecutionOptions = CleanExecutionOptions()
    ) async -> BatchCleanOutput {
        var logs: [String] = []
        appendLog(
            "Starting Speed Clean batch \(batchIndex + 1)/\(totalBatches) for unit \(unitID) with \(segments.count) segment(s).",
            to: &logs
        )
        await progressSink?.report(.heuristicCleaning(batchIndex: batchIndex, totalBatches: totalBatches))

        let localResults = segments.map { segment in
            SegmentCleanResult(
                segmentID: segment.id,
                cleanedText: cleanSegmentText(
                    segment,
                    profile: profile,
                    repeatedNoiseLineKeys: repeatedNoiseLineKeys
                ),
                deliveryMode: .onDevice,
                debugMethod: .local,
                attemptedOnDeviceModel: false,
                attemptedServerFallback: false,
                errors: [],
                logs: []
            )
        }

        appendLog(
            "Heuristic cleaning completed for batch \(batchIndex + 1)/\(totalBatches).",
            to: &logs
        )

        // --- Resolve cleaning strategy ---
        let strategy = resolveCleaningStrategy()
        appendLog("Cleaning strategy: \(strategy.rawValue)", to: &logs)

        var attemptedOnDevice = false
        var accumulatedErrors: [String] = []

        // --- Foundation Models (if strategy says FM is primary) ---
        if strategy == .foundationModelsPrimary && executionOptions.allowOnDeviceModel {
            let modelAttempt = await cleanWithFoundationModelIfAvailable(
                segments: segments,
                unitID: unitID,
                unitTitle: unitTitle,
                profile: profile,
                repeatedNoiseLineKeys: repeatedNoiseLineKeys,
                localResults: localResults,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                progressSink: progressSink,
                executionOptions: executionOptions
            )
            attemptedOnDevice = modelAttempt.attempted
            logs.append(contentsOf: modelAttempt.logs)
            if let errorMessage = modelAttempt.errorMessage {
                accumulatedErrors.append(errorMessage)
            }

            if let fmResults = modelAttempt.results {
                return BatchCleanOutput(results: attachLogs(logs, to: fmResults), logs: logs)
            }
        }

        guard executionOptions.allowServerFallback else {
            appendLog("Server fallback is disabled for this run.", to: &logs)
            return BatchCleanOutput(
                results: annotateLocalResults(
                    localResults,
                    attemptedOnDeviceModel: attemptedOnDevice,
                    attemptedServerFallback: false,
                    errors: accumulatedErrors,
                    logs: logs
                ),
                logs: logs
            )
        }

        if let skipReason = serverCleanupSkipReason(for: segments) {
            appendLog(skipReason.message, to: &logs)
            return BatchCleanOutput(
                results: annotateLocalResults(
                    localResults,
                    attemptedOnDeviceModel: attemptedOnDevice,
                    attemptedServerFallback: false,
                    errors: accumulatedErrors,
                    logs: logs
                ),
                logs: logs
            )
        }

        appendLog("Attempting Supabase speed-clean fallback.", to: &logs)
        await progressSink?.report(.serverFallback(batchIndex: batchIndex, totalBatches: totalBatches))

        do {
            let response = try await SupabaseManager.shared.speedCleanSegments(
                profile: profile,
                unitID: unitID,
                unitTitle: unitTitle,
                segments: segments,
                model: serverFallbackModel
            )
            appendLog("Supabase speed-clean returned \(response.count) cleaned segment(s).", to: &logs)
            let serverTextBySegmentID = Dictionary(uniqueKeysWithValues: response.map { ($0.segmentID, $0.cleanedText) })
            let localMap = Dictionary(uniqueKeysWithValues: localResults.map { ($0.segmentID, $0) })

            let results = segments.map { segment in
                if let cleanedText = serverTextBySegmentID[segment.id],
                   !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return SegmentCleanResult(
                        segmentID: segment.id,
                        cleanedText: normalizeModelCleanedText(
                            cleanedText,
                            originalSegment: segment,
                            profile: profile,
                            repeatedNoiseLineKeys: repeatedNoiseLineKeys
                        ),
                        deliveryMode: .serverFallback,
                        debugMethod: .serverFallback,
                        attemptedOnDeviceModel: attemptedOnDevice,
                        attemptedServerFallback: true,
                        errors: accumulatedErrors,
                        logs: []
                    )
                }

                let message = "Supabase speed-clean returned no cleaned text for segment \(segment.id), so the local cleaned text was kept."
                appendLog(message, to: &logs)
                var errors = accumulatedErrors
                errors.append(message)

                let fallback = localMap[segment.id] ?? SegmentCleanResult(
                    segmentID: segment.id,
                    cleanedText: cleanSegmentText(
                        segment,
                        profile: profile,
                        repeatedNoiseLineKeys: repeatedNoiseLineKeys
                    ),
                    deliveryMode: .onDevice,
                    debugMethod: .local,
                    attemptedOnDeviceModel: false,
                    attemptedServerFallback: false,
                    errors: [],
                    logs: []
                )

                return SegmentCleanResult(
                    segmentID: fallback.segmentID,
                    cleanedText: fallback.cleanedText,
                    deliveryMode: fallback.deliveryMode,
                    debugMethod: localDebugMethod(
                        attemptedOnDeviceModel: attemptedOnDevice,
                        attemptedServerFallback: true
                    ),
                    attemptedOnDeviceModel: attemptedOnDevice,
                    attemptedServerFallback: true,
                    errors: errors,
                    logs: []
                )
            }
            return BatchCleanOutput(results: attachLogs(logs, to: results), logs: logs)
        } catch {
            let message = "Supabase speed-clean failed: \(error.localizedDescription)"
            appendLog(message, to: &logs)
            accumulatedErrors.append(message)

            // Trip the circuit breaker — disable server fallback for 5 minutes
            // to prevent spamming the edge function with requests that will fail.
            serverFallbackDisabledUntil = Date().addingTimeInterval(300)

            return BatchCleanOutput(
                results: annotateLocalResults(
                    localResults,
                    attemptedOnDeviceModel: attemptedOnDevice,
                    attemptedServerFallback: true,
                    errors: accumulatedErrors,
                    logs: logs
                ),
                logs: logs
            )
        }
    }

    private func cleanWithFoundationModelIfAvailable(
        segments: [ContentSegment],
        unitID: String,
        unitTitle: String?,
        profile: SpeedCleanProfile,
        repeatedNoiseLineKeys: Set<String>,
        localResults: [SegmentCleanResult],
        batchIndex: Int,
        totalBatches: Int,
        progressSink: (any SpeedCleanProgressSink)?,
        executionOptions: CleanExecutionOptions
    ) async -> ModelAttemptResult {
        guard executionOptions.allowOnDeviceModel else {
            var logs: [String] = []
            appendLog("On-device model polishing is disabled for this run.", to: &logs)
            return ModelAttemptResult(results: nil, attempted: false, logs: logs, errorMessage: nil)
        }
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await cleanWithFoundationModel(
                segments: segments,
                unitID: unitID,
                unitTitle: unitTitle,
                profile: profile,
                repeatedNoiseLineKeys: repeatedNoiseLineKeys,
                localResults: localResults,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                progressSink: progressSink
            )
        }
#endif
        var logs: [String] = []
        appendLog("Foundation Models are unavailable on this OS version.", to: &logs)
        return ModelAttemptResult(results: nil, attempted: false, logs: logs, errorMessage: nil)
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func cleanWithFoundationModel(
        segments: [ContentSegment],
        unitID: String,
        unitTitle: String?,
        profile: SpeedCleanProfile,
        repeatedNoiseLineKeys: Set<String>,
        localResults: [SegmentCleanResult],
        batchIndex: Int,
        totalBatches: Int,
        progressSink: (any SpeedCleanProgressSink)?
    ) async -> ModelAttemptResult {
        var logs: [String] = []
        guard case .available = SystemLanguageModel.default.availability else {
            appendLog("Foundation Models are unavailable on this device.", to: &logs)
            return ModelAttemptResult(results: nil, attempted: false, logs: logs, errorMessage: nil)
        }

        let localMap = Dictionary(uniqueKeysWithValues: localResults.map { ($0.segmentID, $0) })
        let promptSegments = segments.compactMap { segment -> ModelPromptSegment? in
            guard artifactReplacement(for: segment) == nil,
                  let localResult = localMap[segment.id] else {
                return nil
            }

            let baselineText = localResult.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baselineText.isEmpty else { return nil }

            return ModelPromptSegment(
                segmentID: segment.id,
                text: baselineText,
                structuralKind: segment.structuralKind?.rawValue
            )
        }

        guard !promptSegments.isEmpty else {
            appendLog("On-device model skipped because every segment was handled locally or by deterministic artifact replacement.", to: &logs)
            return ModelAttemptResult(results: nil, attempted: false, logs: logs, errorMessage: nil)
        }

        do {
            appendLog(
                "Attempting on-device model polishing for batch \(batchIndex + 1)/\(totalBatches) with \(promptSegments.count) prompt segment(s).",
                to: &logs
            )
            await progressSink?.report(.onDevicePolishing(batchIndex: batchIndex, totalBatches: totalBatches))
            let session = LanguageModelSession(instructions: structuredSpeedCleanInstructions)
            let prompt = try foundationModelPrompt(
                profile: profile,
                unitID: unitID,
                unitTitle: unitTitle,
                segments: promptSegments
            )
            let response = try await session.respond(to: prompt)
            let modelTextBySegmentID = try parseModelResponse(response.content)

            guard !modelTextBySegmentID.isEmpty else {
                let message = "On-device model returned an empty response payload."
                appendLog(message, to: &logs)
                return ModelAttemptResult(results: nil, attempted: true, logs: logs, errorMessage: message)
            }

            appendLog("On-device model returned \(modelTextBySegmentID.count) cleaned segment(s).", to: &logs)

            let results = segments.map { segment in
                if let cleanedText = modelTextBySegmentID[segment.id],
                   !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return SegmentCleanResult(
                        segmentID: segment.id,
                        cleanedText: normalizeModelCleanedText(
                            cleanedText,
                            originalSegment: segment,
                            profile: profile,
                            repeatedNoiseLineKeys: repeatedNoiseLineKeys
                        ),
                        deliveryMode: .onDevice,
                        debugMethod: .onDeviceModel,
                        attemptedOnDeviceModel: true,
                        attemptedServerFallback: false,
                        errors: [],
                        logs: []
                    )
                }

                let fallbackMessage = "On-device model returned no cleaned text for segment \(segment.id), so the local cleaned text was kept."
                appendLog(fallbackMessage, to: &logs)

                let fallback = localMap[segment.id] ?? SegmentCleanResult(
                    segmentID: segment.id,
                    cleanedText: cleanSegmentText(
                        segment,
                        profile: profile,
                        repeatedNoiseLineKeys: repeatedNoiseLineKeys
                    ),
                    deliveryMode: .onDevice,
                    debugMethod: .local,
                    attemptedOnDeviceModel: false,
                    attemptedServerFallback: false,
                    errors: [],
                    logs: []
                )

                return SegmentCleanResult(
                    segmentID: fallback.segmentID,
                    cleanedText: fallback.cleanedText,
                    deliveryMode: fallback.deliveryMode,
                    debugMethod: .localAfterOnDeviceFailure,
                    attemptedOnDeviceModel: true,
                    attemptedServerFallback: false,
                    errors: [fallbackMessage],
                    logs: []
                )
            }
            return ModelAttemptResult(results: results, attempted: true, logs: logs, errorMessage: nil)
        } catch {
            let message = "On-device model failed: \(error.localizedDescription)"
            appendLog(message, to: &logs)
            return ModelAttemptResult(results: nil, attempted: true, logs: logs, errorMessage: message)
        }
    }
#endif

    private func serverCleanupSkipReason(for segments: [ContentSegment]) -> ServerCleanupSkipReason? {
        // Circuit breaker: skip if a recent call failed (prevents spamming on auth errors)
        if let disabledUntil = serverFallbackDisabledUntil, Date() < disabledUntil {
            return .circuitBreakerOpen
        }
        guard SupabaseManager.shared.client != nil else { return .unavailableClient }
        guard SupabaseManager.shared.hasAuthenticatedSession else { return .unauthenticatedSession }
        let totalCharacters = segments.reduce(into: 0) { partialResult, segment in
            partialResult += segment.text.count
        }
        guard totalCharacters <= maxBatchCharacters else { return .batchTooLarge }
        return nil
    }

    private func cleanSegmentText(
        _ segment: ContentSegment,
        profile: SpeedCleanProfile,
        repeatedNoiseLineKeys: Set<String>
    ) -> String {
        if let artifactPlaceholder = artifactReplacement(for: segment) {
            return artifactPlaceholder
        }

        return cleanText(
            segment.text,
            profile: profile,
            repeatedNoiseLineKeys: repeatedNoiseLineKeys
        )
    }

    private func normalizeModelCleanedText(
        _ text: String,
        originalSegment: ContentSegment,
        profile: SpeedCleanProfile,
        repeatedNoiseLineKeys: Set<String>
    ) -> String {
        if let artifactPlaceholder = artifactReplacement(for: originalSegment) {
            return artifactPlaceholder
        }

        let cleaned = cleanText(
            text,
            profile: profile,
            repeatedNoiseLineKeys: repeatedNoiseLineKeys
        )

        if isArtifactPlaceholderText(cleaned) {
            return cleanText(
                originalSegment.text,
                profile: profile,
                repeatedNoiseLineKeys: repeatedNoiseLineKeys
            )
        }

        return cleaned
    }

    private var structuredSpeedCleanInstructions: String {
        """
        You are a text cleaning engine for a word-by-word speed reading app.
        Output ONLY strict JSON in this format: {"segments":[{"segment_id":"...","cleaned_text":"..."}]}.
        No commentary, no markdown, no explanations.

        GOAL: Transform each input segment into clean, linear, readable prose that flows naturally when displayed one word at a time.

        REMOVE entirely:
        - Footnotes, endnotes, and their reference markers like [1], ¹, and *
        - Page numbers, headers, footers, and running titles
        - Figure, table, and image captions and labels when they are not needed in the reading flow
        - URLs, DOIs, citation blocks, and bibliography entries
        - Anything that is metadata rather than content

        REPLACE confirmed non-prose artifacts with one short placeholder:
        - Tables -> "[ Table: <topic> ]"
        - Images, figures, charts, and diagrams -> "[ Image: <topic> ]"
        - Code blocks -> "[ Code: <language or purpose> ]"
        - Complex math or formulas -> "[ Formula: <what it expresses> ]"

        FIX silently:
        - Missing spaces between words
        - Broken hyphenation from line wrapping
        - Inconsistent whitespace and line breaks
        - OCR artifacts and garbled characters

        PRESERVE exactly:
        - The author's words, meaning, and sentence structure
        - Paragraph breaks using a single blank line
        - Proper nouns, terminology, and wording emphasis as plain text only

        Return exactly one cleaned_text for each input segment_id.
        Do not merge, reorder, omit, or explain segments.
        """
    }

    private func foundationModelPrompt(
        profile: SpeedCleanProfile,
        unitID: String,
        unitTitle: String?,
        segments: [ModelPromptSegment]
    ) throws -> String {
        let payload = ModelPromptPayload(
            profile: profile.rawValue,
            unitID: unitID,
            unitTitle: unitTitle,
            segments: segments
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        let json = String(decoding: data, as: UTF8.self)

        return """
        Input JSON:
        \(json)
        """
    }

    private func parseModelResponse(_ text: String) throws -> [String: String] {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(cleaned.utf8)
        let decoded = try JSONDecoder().decode(ModelResponsePayload.self, from: data)
        return Dictionary(uniqueKeysWithValues: decoded.segments.map { ($0.segmentID, $0.cleanedText) })
    }

    private func apply(
        package: SpeedCleanPackage,
        to canonicalPackages: CanonicalDocumentPackages
    ) -> CanonicalDocumentPackages {
        let readyChunkBySegmentID = Dictionary(
            uniqueKeysWithValues: package.chunks
                .filter { $0.status == .ready }
                .map { ($0.segmentID, $0) }
        )

        var segments = canonicalPackages.textAnchorsPackage.segments.sorted { $0.order < $1.order }
        var plainText = ""

        for index in segments.indices {
            let replacement = readyChunkBySegmentID[segments[index].id]?.cleanedText ?? segments[index].text
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

    private func overallStatus(for package: SpeedCleanPackage) -> SpeedCleanOverallStatus {
        let statuses = package.chunks.map(\.status)
        if statuses.allSatisfy({ $0 == .ready }) {
            return .ready
        }
        if statuses.contains(.processing) {
            return .processing
        }
        if statuses.contains(.ready) {
            return .partial
        }
        if statuses.contains(.failed) {
            return .failed
        }
        return .notStarted
    }

    private func overallDeliveryMode(for package: SpeedCleanPackage) -> SpeedCleanDeliveryMode {
        let modes = Set(package.chunks.compactMap(\.deliveryMode))
        if modes.contains(.serverFallback) && modes.contains(.onDevice) {
            return .hybrid
        }
        if modes.contains(.serverFallback) {
            return .serverFallback
        }
        return .onDevice
    }

    private func overallDeliveryMode(for results: [SegmentCleanResult]) -> SpeedCleanDeliveryMode {
        let modes = Set(results.map(\.deliveryMode))
        if modes.contains(.serverFallback) && modes.contains(.onDevice) {
            return .hybrid
        }
        if modes.contains(.serverFallback) {
            return .serverFallback
        }
        return .onDevice
    }

    private func repeatedNoiseLineKeys(in canonicalPackages: CanonicalDocumentPackages) -> Set<String> {
        repeatedNoiseLineKeys(in: canonicalPackages.textAnchorsPackage.segments)
    }

    private func repeatedNoiseLineKeys(in segments: [ContentSegment]) -> Set<String> {
        var counts: [String: Int] = [:]

        for segment in segments {
            for line in segment.text.components(separatedBy: .newlines) {
                let key = normalizedLineKey(for: line)
                guard isRepeatableNoiseLineKey(key) else { continue }
                counts[key, default: 0] += 1
            }
        }

        return Set(counts.compactMap { key, value in
            value >= 3 ? key : nil
        })
    }

    private func annotateLocalResults(
        _ results: [SegmentCleanResult],
        attemptedOnDeviceModel: Bool,
        attemptedServerFallback: Bool,
        errors: [String],
        logs: [String]
    ) -> [SegmentCleanResult] {
        let method = localDebugMethod(
            attemptedOnDeviceModel: attemptedOnDeviceModel,
            attemptedServerFallback: attemptedServerFallback
        )

        return attachLogs(logs, to: results.map { result in
            SegmentCleanResult(
                segmentID: result.segmentID,
                cleanedText: result.cleanedText,
                deliveryMode: result.deliveryMode,
                debugMethod: method,
                attemptedOnDeviceModel: attemptedOnDeviceModel,
                attemptedServerFallback: attemptedServerFallback,
                errors: errors,
                logs: result.logs
            )
        })
    }

    private func attachLogs(_ logs: [String], to results: [SegmentCleanResult]) -> [SegmentCleanResult] {
        results.map { result in
            let combinedLogs = logs + result.logs
            return SegmentCleanResult(
                segmentID: result.segmentID,
                cleanedText: result.cleanedText,
                deliveryMode: result.deliveryMode,
                debugMethod: result.debugMethod,
                attemptedOnDeviceModel: result.attemptedOnDeviceModel,
                attemptedServerFallback: result.attemptedServerFallback,
                errors: result.errors,
                logs: combinedLogs
            )
        }
    }

    private func localDebugMethod(
        attemptedOnDeviceModel: Bool,
        attemptedServerFallback: Bool
    ) -> DebugMethod {
        if attemptedOnDeviceModel && attemptedServerFallback {
            return .localAfterOnDeviceAndServerFailure
        }
        if attemptedServerFallback {
            return .localAfterServerFailure
        }
        if attemptedOnDeviceModel {
            return .localAfterOnDeviceFailure
        }
        return .local
    }

    private func debugSegments(from text: String, structuralKind: StructuralContentKind?) -> [ContentSegment] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let segments = (parts.isEmpty ? [normalized.trimmingCharacters(in: .whitespacesAndNewlines)] : parts)
            .filter { !$0.isEmpty }

        return segments.enumerated().map { index, segmentText in
            ContentSegment(
                id: "debug-segment-\(index)",
                unitID: "debug-unit",
                anchorID: "debug-segment-\(index)",
                kind: .paragraphGroup,
                order: index,
                text: segmentText,
                structuralKind: structuralKind
            )
        }
    }

    private func makeLogLine(_ message: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "[SpeedClean \(formatter.string(from: Date()))] \(message)"
    }

    private func appendLog(_ message: String, to logs: inout [String]) {
        let line = makeLogLine(message)
        logs.append(line)
        print(line)
    }

    private func isRepeatableNoiseLineKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 80 else { return false }
        let digits = key.filter(\.isNumber).count
        let letters = key.filter(\.isLetter).count
        return digits > 0 || letters > 0
    }

    private func normalizedLineKey(for line: String) -> String {
        collapseWhitespace(line).lowercased()
    }

    private func cleanText(
        _ text: String,
        profile: SpeedCleanProfile,
        repeatedNoiseLineKeys: Set<String>
    ) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        normalized = replacingRegex("-\\n(?=[a-z])", in: normalized, with: "")
        normalized = replacingRegex("(?<=[A-Za-z,;:])\\n(?=[a-z])", in: normalized, with: " ")
        normalized = replacingRegex("[ \\t]+", in: normalized, with: " ")
        normalized = replacingRegex("\\n{3,}", in: normalized, with: "\n\n")

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .compactMap { cleanParagraph($0, profile: profile, repeatedNoiseLineKeys: repeatedNoiseLineKeys) }

        let cleaned = paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return fallbackText(from: text)
        }
        return cleaned
    }

    private func cleanParagraph(
        _ paragraph: String,
        profile: SpeedCleanProfile,
        repeatedNoiseLineKeys: Set<String>
    ) -> String? {
        let lines = paragraph.components(separatedBy: .newlines)
        var keptLines: [String] = []

        for line in lines {
            let collapsed = collapseWhitespace(line)
            guard !collapsed.isEmpty else { continue }
            if shouldDropLine(collapsed, profile: profile, repeatedNoiseLineKeys: repeatedNoiseLineKeys) {
                continue
            }
            keptLines.append(collapsed)
        }

        let combined = collapseWhitespace(keptLines.joined(separator: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else { return nil }

        return combined
    }

    private func shouldDropLine(
        _ line: String,
        profile: SpeedCleanProfile,
        repeatedNoiseLineKeys: Set<String>
    ) -> Bool {
        let key = normalizedLineKey(for: line)
        if repeatedNoiseLineKeys.contains(key) {
            return true
        }

        if line.range(of: "^(page\\s+)?\\d+$", options: .regularExpression) != nil {
            return true
        }

        if line.range(of: "^[ivxlcdm]+$", options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        let lowercased = line.lowercased()
        let junkPhrases: [String]
        switch profile {
        case .book:
            junkPhrases = ["all rights reserved", "copyright", "scan by", "digitized by"]
        case .article:
            junkPhrases = ["advertisement", "subscribe", "sign up", "read more", "share this article", "follow us", "cookie policy", "terms of service"]
        case .pdfPaper:
            junkPhrases = ["advertisement", "copyright", "all rights reserved", "preprint", "accepted manuscript"]
        }

        if junkPhrases.contains(where: { lowercased.contains($0) }) {
            return true
        }

        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return true
        }

        return false
    }

    private func artifactReplacement(for segment: ContentSegment) -> String? {
        if segment.structuralKind == .codeBlock {
            return artifactToken(kind: "Code", topic: "code block")
        }

        guard let descriptor = artifactDescriptor(for: segment) else { return nil }
        let kind = artifactTokenKind(for: descriptor, segment: segment)
        let topic = artifactTokenTopic(for: descriptor, kind: kind)
        return artifactToken(kind: kind, topic: topic)
    }

    private func artifactDescriptor(for segment: ContentSegment) -> ArtifactDescriptor? {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { collapseWhitespace($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let symbolCount = trimmed.filter { "|\\/:;+-_=()[]{}".contains($0) }.count
        let explicitMatch = firstMatch(
            pattern: "(?i)^\\s*(figure|fig\\.|table|exhibit|chart|diagram)\\s*([A-Za-z0-9.-]+)?\\s*[:\\-–]?\\s*(.{0,120})",
            in: trimmed
        )
        let hasExplicitMarker = explicitMatch?.count ?? 0 >= 4
        let tabularLineCount = lines.filter { line in
            line.contains("|") ||
                line.contains("\t") ||
                line.range(of: "\\S\\s{2,}\\S", options: .regularExpression) != nil ||
                isNumericHeavyLine(line)
        }.count
        let looksTabular = lines.count >= 2 && tabularLineCount >= 2
        let looksLikeArtifact = hasExplicitMarker || (looksTabular && symbolCount >= 8)

        guard looksLikeArtifact else { return nil }

        if let explicitMatch, explicitMatch.count >= 4 {
            let kindTitle = normalizedArtifactKindTitle(explicitMatch[1])
            let label = explicitMatch[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let descriptor = sanitizedArtifactDescriptor(explicitMatch[3])
            return ArtifactDescriptor(
                kindTitle: kindTitle,
                label: label.isEmpty ? nil : label,
                descriptor: descriptor
            )
        }

        let fallbackDescriptor = bestArtifactDescriptorLine(from: lines)
        let kindTitle = segment.structuralKind == .image ? "Figure" : "Table"
        return ArtifactDescriptor(kindTitle: kindTitle, label: nil, descriptor: fallbackDescriptor)
    }

    private func normalizedArtifactKindTitle(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "fig":
            return "Figure"
        case "table":
            return "Table"
        case "exhibit":
            return "Exhibit"
        case "chart":
            return "Chart"
        case "diagram":
            return "Diagram"
        default:
            return normalized.capitalized
        }
    }

    private func sanitizedArtifactDescriptor(_ value: String) -> String? {
        let collapsed = collapseWhitespace(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        let numberCount = collapsed.filter(\.isNumber).count
        let letterCount = collapsed.filter(\.isLetter).count
        guard letterCount >= 3 || numberCount == 0 else { return nil }
        return String(collapsed.prefix(90)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bestArtifactDescriptorLine(from lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.contains("|"),
                  !trimmed.contains("\t"),
                  trimmed.range(of: "\\S\\s{2,}\\S", options: .regularExpression) == nil else {
                continue
            }

            if let descriptor = sanitizedArtifactDescriptor(trimmed) {
                return descriptor
            }
        }
        return nil
    }

    private func artifactTokenKind(for descriptor: ArtifactDescriptor, segment: ContentSegment) -> String {
        switch descriptor.kindTitle.lowercased() {
        case "table":
            return "Table"
        case "figure", "chart", "diagram", "exhibit":
            return "Image"
        default:
            if segment.structuralKind == .image {
                return "Image"
            }
            return "Table"
        }
    }

    private func artifactTokenTopic(for descriptor: ArtifactDescriptor, kind: String) -> String {
        let candidates: [String] = [descriptor.label, descriptor.descriptor]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

        if !candidates.isEmpty {
            return candidates.joined(separator: " ")
        }

        switch kind {
        case "Image":
            return "illustration"
        case "Code":
            return "code block"
        case "Formula":
            return "equation"
        default:
            return "data"
        }
    }

    private func artifactToken(kind: String, topic: String) -> String {
        "[ \(kind): \(topic) ]"
    }

    private func isNumericHeavyLine(_ line: String) -> Bool {
        let numberCount = line.filter(\.isNumber).count
        let letterCount = line.filter(\.isLetter).count
        return numberCount >= 4 && numberCount >= max(4, letterCount)
    }

    private func isArtifactPlaceholderText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("classic reader mode") ||
            lowercased.contains("document artifacts") ||
            text.range(of: "^\\[\\s*(table|image|code|formula)\\s*:", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func fallbackText(from text: String) -> String {
        collapseWhitespace(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func replacingRegex(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
