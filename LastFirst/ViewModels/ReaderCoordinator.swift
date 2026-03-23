import Foundation
import SwiftUI
import SwiftData
import Combine

private actor ReaderSpeedCleanProgressReporter: SpeedCleanProgressSink {
    private let handler: @Sendable (SpeedCleanProgressEvent) async -> Void

    init(handler: @escaping @Sendable (SpeedCleanProgressEvent) async -> Void) {
        self.handler = handler
    }

    func report(_ event: SpeedCleanProgressEvent) async {
        await handler(event)
    }
}

@MainActor
class ReaderCoordinator: ObservableObject {
    enum PresentationState: Equatable {
        case dismissed
        case expanded
        case minimized
    }

    enum ReaderActivityPhase: Equatable {
        case loadingSourceText
        case preparingSpeedClean
        case heuristicCleaning(batchIndex: Int, totalBatches: Int)
        case onDevicePolishing(batchIndex: Int, totalBatches: Int)
        case serverFallback(batchIndex: Int, totalBatches: Int)
        case applyingPreparedText
        case prefetchPreparing(chapterTitle: String?)
        case prefetchHeuristicCleaning(chapterTitle: String?, batchIndex: Int, totalBatches: Int)
        case prefetchOnDevicePolishing(chapterTitle: String?, batchIndex: Int, totalBatches: Int)
        case prefetchServerFallback(chapterTitle: String?, batchIndex: Int, totalBatches: Int)

        var overlayText: String? {
            switch self {
            case .loadingSourceText:
                return "Loading text..."
            case .preparingSpeedClean,
                 .heuristicCleaning,
                 .onDevicePolishing,
                 .serverFallback,
                 .applyingPreparedText:
                return "Polishing..."
            case .prefetchPreparing,
                 .prefetchHeuristicCleaning,
                 .prefetchOnDevicePolishing,
                 .prefetchServerFallback:
                return nil
            }
        }

        var bannerText: String? {
            switch self {
            case .prefetchPreparing,
                 .prefetchHeuristicCleaning,
                 .prefetchOnDevicePolishing,
                 .prefetchServerFallback:
                return "Polishing..."
            case .loadingSourceText,
                 .preparingSpeedClean,
                 .heuristicCleaning,
                 .onDevicePolishing,
                 .serverFallback,
                 .applyingPreparedText:
                return nil
            }
        }
    }

    @Published private(set) var viewModel: ReadingViewModel?
    @Published var presentationState: PresentationState = .dismissed
    @Published private(set) var activeItem: LibraryItem?
    @Published private(set) var canonicalPackages: CanonicalDocumentPackages?
    @Published private(set) var coverImageData: Data?
    @Published private(set) var isLoadingContent: Bool = false
    @Published var loadingError: String?
    @Published private(set) var speedCleanPackage: SpeedCleanPackage?
    @Published private(set) var speedCleanStatus: SpeedCleanOverallStatus = .notStarted
    @Published private(set) var isPolishingText: Bool = false
    @Published private(set) var activeLoadingPhase: ReaderActivityPhase?
    @Published private(set) var backgroundActivityPhase: ReaderActivityPhase?
    @Published private(set) var completionBannerText: String?
    @Published var activeVariant: TextVariant?
    var loadedTextVariantPackage: TextVariantPackage?

    private(set) var metricsTracker: ReadingMetricsTracker?
    private var loadingTask: Task<Void, Never>?
    private var completionBannerTask: Task<Void, Never>?
    private var readingProgressObservation: AnyCancellable?
    private(set) var currentSource: DocumentSource?
    private var unitIDByChapterID: [UUID: String] = [:]
    private var prefetchedUnitIDs: Set<String> = []
    var syncService: ReadingMetricsSyncService?

    func openItem(_ item: LibraryItem, appState: AppState) {
        // If same item already active, just expand
        if activeItem?.documentId == item.documentId, viewModel != nil {
            presentationState = .expanded
            return
        }

        // Finalize previous session metrics if any
        finalizeCurrentSession()

        // Save progress of previous session if any
        if let vm = viewModel, let prevItem = activeItem {
            saveProgress(vm: vm, item: prevItem, appState: appState)
        }

        // Create fresh VM and load content
        let vm = ReadingViewModel()
        self.viewModel = vm
        self.activeItem = item
        self.canonicalPackages = nil
        self.speedCleanPackage = nil
        self.speedCleanStatus = .notStarted
        self.currentSource = mapLibrarySource(item.source)
        self.unitIDByChapterID = [:]
        self.prefetchedUnitIDs = []
        self.activeLoadingPhase = nil
        self.backgroundActivityPhase = nil
        clearCompletionBanner()
        self.coverImageData = appState.getCoverImage(for: item.documentId)
        self.presentationState = .expanded

        // Create metrics tracker
        let tracker = ReadingMetricsTracker(
            documentId: item.documentId,
            startTokenIndex: item.progress.tokenIndex,
            readingMode: appState.settings.defaultReadingMode
        )
        self.metricsTracker = tracker
        vm.metricsTracker = tracker

        // Update last opened
        var updatedItem = item
        updatedItem.lastOpenedAt = Date()
        appState.updateItem(updatedItem)

        loadingTask?.cancel()
        loadingTask = Task {
            await loadContent(for: item, vm: vm, appState: appState)
        }
    }

    func minimize() {
        viewModel?.pause()
        // Finalize metrics on minimize — a new tracker will be created on next openItem/expand if needed
        finalizeCurrentSession()
        presentationState = .minimized
    }

    func expand() {
        guard presentationState == .minimized else { return }
        presentationState = .expanded

        // Start a new metrics session on re-expand
        if let item = activeItem, let vm = viewModel, metricsTracker == nil {
            let tracker = ReadingMetricsTracker(
                documentId: item.documentId,
                startTokenIndex: vm.getCurrentProgress().tokenIndex,
                readingMode: vm.readingMode
            )
            self.metricsTracker = tracker
            vm.metricsTracker = tracker
        }
    }

    var isSheetPresented: Binding<Bool> {
        Binding<Bool>(
            get: { self.presentationState == .expanded },
            set: { newValue in
                if !newValue {
                    self.minimize()
                }
            }
        )
    }

    func dismiss(appState: AppState) {
        if let vm = viewModel, let item = activeItem {
            saveProgress(vm: vm, item: item, appState: appState)
        }
        viewModel?.pause()
        finalizeCurrentSession()
        loadingTask?.cancel()
        loadingTask = nil
        readingProgressObservation?.cancel()
        readingProgressObservation = nil
        viewModel = nil
        activeItem = nil
        canonicalPackages = nil
        speedCleanPackage = nil
        speedCleanStatus = .notStarted
        isPolishingText = false
        activeVariant = nil
        activeLoadingPhase = nil
        backgroundActivityPhase = nil
        clearCompletionBanner()
        currentSource = nil
        unitIDByChapterID = [:]
        prefetchedUnitIDs = []
        coverImageData = nil
        presentationState = .dismissed
    }

    // MARK: - Content Loading

    private func loadContent(for item: LibraryItem, vm: ReadingViewModel, appState: AppState) async {
        vm.isLoading = true
        vm.loadingError = nil
        isLoadingContent = true
        activeLoadingPhase = .loadingSourceText
        clearCompletionBanner()
        let progressSink = foregroundProgressSink()

        defer {
            vm.isLoading = false
            isLoadingContent = false
            activeLoadingPhase = nil
        }

        do {
            let packages = try await loadOrIngestCanonicalPackages(item: item)
            self.canonicalPackages = packages

            let source = mapLibrarySource(item.source)
            self.currentSource = source
            let priorityUnitID = prioritizedUnitID(for: item, packages: packages)
            activeLoadingPhase = .preparingSpeedClean
            let prepared = await SpeedCleanService.shared.preparedPackages(
                documentId: item.documentId,
                source: source,
                canonicalPackages: packages,
                priorityUnitID: priorityUnitID,
                progressSink: progressSink
            )

            self.speedCleanPackage = prepared.speedCleanPackage
            self.speedCleanStatus = prepared.speedCleanPackage.status

            activeLoadingPhase = .applyingPreparedText
            applyReaderDocument(
                from: prepared.packages,
                canonicalPackages: packages,
                source: source,
                vm: vm,
                startTokenIndex: item.progress.tokenIndex,
                appState: appState
            )

            configureReadingProgressObservation(for: vm)

            if vm.words.isEmpty && vm.loadingError == nil {
                loadingError = "This book appears to be empty or could not be read."
            }

            appState.populateFootnotes(from: packages, documentId: item.documentId)
            appState.loadPendingImages(for: item.documentId)

            // Mark content as downloaded so the ribbon fills in
            if item.downloadState != .downloaded {
                var updatedItem = item
                updatedItem.downloadState = .downloaded
                appState.updateItem(updatedItem)
            }

            showDoneBanner()

        } catch {
            vm.loadingError = error
            loadingError = error.localizedDescription
            clearCompletionBanner()
        }
    }

    private func prioritizedUnitID(for item: LibraryItem, packages: CanonicalDocumentPackages) -> String? {
        if let lastChapterTitle = item.lastChapterTitle,
           let matched = packages.textAnchorsPackage.units.first(where: { $0.title == lastChapterTitle }) {
            return matched.id
        }

        return packages.textAnchorsPackage.units.sorted { $0.order < $1.order }.first?.id
    }

    private func applyReaderDocument(
        from packages: CanonicalDocumentPackages,
        canonicalPackages: CanonicalDocumentPackages,
        source: DocumentSource,
        vm: ReadingViewModel,
        startTokenIndex: Int,
        appState: AppState,
        targetChapterTitle: String? = nil,
        preserveReaderConfiguration: Bool = false
    ) {
        let preservedWPM = vm.wordsPerMinute
        let preservedReadingMode = vm.readingMode

        let readerDocument = CanonicalDocumentAdapter.buildReaderDocument(
            from: packages,
            source: source,
            ingestionVersion: DocumentIngestionService.currentIngestionVersion
        )

        unitIDByChapterID = chapterUnitIDs(readerDocument: readerDocument, canonicalPackages: canonicalPackages)
        prefetchedUnitIDs = Set(
            unitIDByChapterID.compactMap { chapterID, unitID in
                guard let chapter = readerDocument.chapters.first(where: { $0.id == chapterID }), chapterStatus(chapter) == .ready else {
                    return nil
                }
                return unitID
            }
        )

        vm.loadContent(
            tokens: readerDocument.tokens,
            chapters: readerDocument.chapters,
            blocks: readerDocument.blocks,
            startTokenIndex: startTokenIndex
        )

        vm.wordsPerMinute = preserveReaderConfiguration ? preservedWPM : appState.settings.defaultWPM
        vm.setSoftStartPercentage(appState.settings.softStartPercentage)
        vm.setParagraphBreathMs(appState.settings.paragraphBreathMs)
        vm.readingMode = preserveReaderConfiguration ? preservedReadingMode : appState.settings.defaultReadingMode

        if let targetChapterTitle,
           let targetChapter = vm.chapters.first(where: { $0.title == targetChapterTitle }) {
            vm.goToChapter(targetChapter)
        }

        if vm.readingMode == .stream {
            vm.initializeStreamMode()
        }

        if !vm.words.isEmpty, var updatedItem = self.activeItem {
            updatedItem.wordCount = vm.words.count
            self.activeItem = updatedItem
            appState.updateItem(updatedItem)
        }
    }

    private func chapterUnitIDs(
        readerDocument: ReaderDocument,
        canonicalPackages: CanonicalDocumentPackages
    ) -> [UUID: String] {
        let units = canonicalPackages.textAnchorsPackage.units.sorted { $0.order < $1.order }
        let chapters = readerDocument.chapters
        let count = min(units.count, chapters.count)

        var mapping: [UUID: String] = [:]
        for index in 0..<count {
            mapping[chapters[index].id] = units[index].id
        }
        return mapping
    }

    private func configureReadingProgressObservation(for vm: ReadingViewModel) {
        readingProgressObservation?.cancel()
        readingProgressObservation = vm.$currentWordIndex
            .sink { [weak self, weak vm] _ in
                guard let self, let vm else { return }
                self.prefetchUpcomingChapterIfNeeded(using: vm)
            }
    }

    private func prefetchUpcomingChapterIfNeeded(using vm: ReadingViewModel) {
        guard shouldUseSpeedCleanPrompting,
              vm.chapterProgress >= 0.5,
              vm.currentChapterIndex + 1 < vm.chapters.count else {
            return
        }

        let nextChapter = vm.chapters[vm.currentChapterIndex + 1]
        guard let unitID = unitIDByChapterID[nextChapter.id], !prefetchedUnitIDs.contains(unitID) else {
            return
        }

        prefetchedUnitIDs.insert(unitID)
        backgroundActivityPhase = .prefetchPreparing(chapterTitle: nextChapter.title)

        Task { @MainActor [weak self] in
            guard let self,
                  let item = self.activeItem,
                  let source = self.currentSource,
                  let canonicalPackages = self.canonicalPackages else {
                return
            }

            let progressSink = self.backgroundProgressSink(chapterTitle: nextChapter.title)

            let prepared = await SpeedCleanService.shared.polishUnit(
                documentId: item.documentId,
                source: source,
                canonicalPackages: canonicalPackages,
                unitID: unitID,
                progressSink: progressSink
            )

            guard self.activeItem?.documentId == item.documentId else { return }
            self.speedCleanPackage = prepared.speedCleanPackage
            self.speedCleanStatus = prepared.speedCleanPackage.status
            self.backgroundActivityPhase = nil
        }
    }

    private var shouldUseSpeedCleanPrompting: Bool {
        guard let currentSource else { return false }
        if case .localFile(let local) = currentSource {
            return local.fileType == .epub
        }
        return false
    }

    func isChapterReady(_ chapter: Chapter) -> Bool {
        chapterStatus(chapter) == .ready
    }

    func chapterStatus(_ chapter: Chapter) -> SpeedCleanOverallStatus {
        guard shouldUseSpeedCleanPrompting,
              let unitID = unitIDByChapterID[chapter.id],
              let speedCleanPackage,
              let canonicalPackages else {
            return shouldUseSpeedCleanPrompting ? .notStarted : .ready
        }

        let segmentIDs = canonicalPackages.textAnchorsPackage.segments
            .filter { $0.unitID == unitID }
            .map(\.id)
        return speedCleanPackage.unitStatus(unitID, segmentIDs: segmentIDs)
    }

    func shouldPromptForPolish(_ chapter: Chapter) -> Bool {
        shouldUseSpeedCleanPrompting && !isChapterReady(chapter)
    }

    func polishChapterAndNavigate(_ chapter: Chapter, appState: AppState) async {
        guard let item = activeItem,
              let source = currentSource,
              let canonicalPackages,
              let vm = viewModel,
              let unitID = unitIDByChapterID[chapter.id] else {
            return
        }

        isPolishingText = true
        activeLoadingPhase = .preparingSpeedClean
        clearCompletionBanner()
        let progressSink = foregroundProgressSink()

        defer {
            isPolishingText = false
            activeLoadingPhase = nil
        }

        let preservedTokenIndex = vm.getCurrentProgress().tokenIndex
        let prepared = await SpeedCleanService.shared.polishUnit(
            documentId: item.documentId,
            source: source,
            canonicalPackages: canonicalPackages,
            unitID: unitID,
            progressSink: progressSink
        )

        guard activeItem?.documentId == item.documentId else {
            return
        }

        speedCleanPackage = prepared.speedCleanPackage
        speedCleanStatus = prepared.speedCleanPackage.status
        activeLoadingPhase = .applyingPreparedText
        applyReaderDocument(
            from: prepared.packages,
            canonicalPackages: canonicalPackages,
            source: source,
            vm: vm,
            startTokenIndex: preservedTokenIndex,
            appState: appState,
            targetChapterTitle: chapter.title,
            preserveReaderConfiguration: true
        )
        showDoneBanner()
    }

    // MARK: - Text Variant Support

    func unitIDForChapter(_ chapter: Chapter) -> String? {
        unitIDByChapterID[chapter.id]
    }

    func applyVariant(_ variant: TextVariant, modifiedPackages: CanonicalDocumentPackages, appState: AppState? = nil) {
        guard let vm = viewModel,
              let canonicalPackages,
              let source = currentSource else { return }

        let preservedTokenIndex = vm.getCurrentProgress().tokenIndex
        activeVariant = variant

        if let appState {
            applyReaderDocument(
                from: modifiedPackages,
                canonicalPackages: canonicalPackages,
                source: source,
                vm: vm,
                startTokenIndex: preservedTokenIndex,
                appState: appState,
                preserveReaderConfiguration: true
            )
        } else {
            // Lightweight re-apply without appState — preserve all VM settings
            let readerDocument = CanonicalDocumentAdapter.buildReaderDocument(
                from: modifiedPackages,
                source: source,
                ingestionVersion: DocumentIngestionService.currentIngestionVersion
            )
            let preservedWPM = vm.wordsPerMinute
            let preservedMode = vm.readingMode
            vm.loadContent(
                tokens: readerDocument.tokens,
                chapters: readerDocument.chapters,
                blocks: readerDocument.blocks,
                startTokenIndex: preservedTokenIndex
            )
            vm.wordsPerMinute = preservedWPM
            vm.readingMode = preservedMode
            if vm.readingMode == .stream {
                vm.initializeStreamMode()
            }
        }
    }

    func toggleSpeedClean(appState: AppState) {
        if activeVariant?.kind == .speedClean {
            revertToOriginal(appState: appState)
        } else if let speedCleanPackage, let canonicalPackages {
            let modifiedPackages = applySpeedCleanChunks(speedCleanPackage, to: canonicalPackages)
            let variant = TextVariant(
                documentId: activeItem?.documentId ?? UUID(),
                unitID: "",
                name: "Optimized",
                kind: .speedClean,
                status: .ready
            )
            applyVariant(variant, modifiedPackages: modifiedPackages, appState: appState)
        }
    }

    func revertToOriginal(appState: AppState) {
        guard let vm = viewModel,
              let canonicalPackages,
              let source = currentSource else { return }

        let preservedTokenIndex = vm.getCurrentProgress().tokenIndex
        activeVariant = nil

        applyReaderDocument(
            from: canonicalPackages,
            canonicalPackages: canonicalPackages,
            source: source,
            vm: vm,
            startTokenIndex: preservedTokenIndex,
            appState: appState,
            preserveReaderConfiguration: true
        )
    }

    func clearVariant(appState: AppState? = nil) {
        guard let vm = viewModel,
              let canonicalPackages,
              let source = currentSource else { return }

        let preservedTokenIndex = vm.getCurrentProgress().tokenIndex
        activeVariant = nil

        // Reconstruct speed-cleaned packages by replaying chunk replacements
        let packagesToApply: CanonicalDocumentPackages
        if let speedCleanPackage {
            packagesToApply = applySpeedCleanChunks(speedCleanPackage, to: canonicalPackages)
        } else {
            packagesToApply = canonicalPackages
        }

        if let appState {
            applyReaderDocument(
                from: packagesToApply,
                canonicalPackages: canonicalPackages,
                source: source,
                vm: vm,
                startTokenIndex: preservedTokenIndex,
                appState: appState,
                preserveReaderConfiguration: true
            )
        } else {
            let readerDocument = CanonicalDocumentAdapter.buildReaderDocument(
                from: packagesToApply,
                source: source,
                ingestionVersion: DocumentIngestionService.currentIngestionVersion
            )
            let preservedWPM = vm.wordsPerMinute
            let preservedMode = vm.readingMode
            vm.loadContent(
                tokens: readerDocument.tokens,
                chapters: readerDocument.chapters,
                blocks: readerDocument.blocks,
                startTokenIndex: preservedTokenIndex
            )
            vm.wordsPerMinute = preservedWPM
            vm.readingMode = preservedMode
            if vm.readingMode == .stream {
                vm.initializeStreamMode()
            }
        }
    }

    /// Mirrors SpeedCleanService.apply — replays speed-clean chunk replacements.
    private func applySpeedCleanChunks(
        _ package: SpeedCleanPackage,
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

    var loadingOverlayText: String {
        activeLoadingPhase?.overlayText ?? (isPolishingText ? "Polishing..." : "Loading text...")
    }

    var speedCleanBannerText: String? {
        if let completionBannerText {
            return completionBannerText
        }

        if let backgroundActivityPhase {
            return backgroundActivityPhase.bannerText
        }

        return nil
    }

    private func clearCompletionBanner() {
        completionBannerTask?.cancel()
        completionBannerTask = nil
        completionBannerText = nil
    }

    private func showDoneBanner() {
        clearCompletionBanner()
        completionBannerText = "Done"
        completionBannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completionBannerText = nil
                self?.completionBannerTask = nil
            }
        }
    }

    private func foregroundProgressSink() -> ReaderSpeedCleanProgressReporter {
        ReaderSpeedCleanProgressReporter { [weak self] event in
            await MainActor.run {
                self?.activeLoadingPhase = self?.foregroundPhase(for: event)
            }
        }
    }

    private func backgroundProgressSink(chapterTitle: String?) -> ReaderSpeedCleanProgressReporter {
        ReaderSpeedCleanProgressReporter { [weak self] event in
            await MainActor.run {
                self?.backgroundActivityPhase = self?.backgroundPhase(for: event, chapterTitle: chapterTitle)
            }
        }
    }

    private func foregroundPhase(for event: SpeedCleanProgressEvent) -> ReaderActivityPhase {
        switch event {
        case .heuristicCleaning(let batchIndex, let totalBatches):
            return .heuristicCleaning(batchIndex: batchIndex, totalBatches: totalBatches)
        case .onDevicePolishing(let batchIndex, let totalBatches):
            return .onDevicePolishing(batchIndex: batchIndex, totalBatches: totalBatches)
        case .serverFallback(let batchIndex, let totalBatches):
            return .serverFallback(batchIndex: batchIndex, totalBatches: totalBatches)
        }
    }

    private func backgroundPhase(for event: SpeedCleanProgressEvent, chapterTitle: String?) -> ReaderActivityPhase {
        switch event {
        case .heuristicCleaning(let batchIndex, let totalBatches):
            return .prefetchHeuristicCleaning(chapterTitle: chapterTitle, batchIndex: batchIndex, totalBatches: totalBatches)
        case .onDevicePolishing(let batchIndex, let totalBatches):
            return .prefetchOnDevicePolishing(chapterTitle: chapterTitle, batchIndex: batchIndex, totalBatches: totalBatches)
        case .serverFallback(let batchIndex, let totalBatches):
            return .prefetchServerFallback(chapterTitle: chapterTitle, batchIndex: batchIndex, totalBatches: totalBatches)
        }
    }

    private func loadOrIngestCanonicalPackages(item: LibraryItem) async throws -> CanonicalDocumentPackages {
        let ingestion = DocumentIngestionService()
        return try await ingestion.ingestCanonicalPackages(
            source: mapLibrarySource(item.source),
            documentId: item.documentId
        )
    }

    private func mapLibrarySource(_ source: LibrarySource) -> DocumentSource {
        switch source {
        case .localFile(let local):
            return .localFile(.init(url: local.fileURL, fileType: local.fileType))
        case .web(let web):
            return .web(.init(url: web.url, lastRefreshedAt: web.lastRefreshedAt))
        case .curated(let curated):
            if let sourceUrl = curated.sourceUrl {
                return .web(.init(url: sourceUrl))
            }
            // Fallback: use a placeholder URL — curated items may not be locally available yet
            return .web(.init(url: URL(string: "about:blank")!))
        }
    }

    // MARK: - Progress

    func saveProgress(appState: AppState) {
        guard let vm = viewModel, let item = activeItem else { return }
        saveProgress(vm: vm, item: item, appState: appState)
    }

    private func saveProgress(vm: ReadingViewModel, item: LibraryItem, appState: AppState) {
        var updatedItem = item
        updatedItem.progress = vm.getCurrentProgress()
        updatedItem.lastOpenedAt = Date()
        updatedItem.lastChapterTitle = vm.currentChapter?.title
        appState.updateItem(updatedItem)
    }

    // MARK: - Summarized Content

    func openSummarizedContent(text: String, title: String, sourceUrl: URL?, appState: AppState) {
        // Create a synthetic LibraryItem for the summary
        let documentId = UUID()
        let source: LibrarySource
        if let sourceUrl {
            source = .web(.init(url: sourceUrl))
        } else {
            source = .web(.init(url: URL(string: "about:blank")!))
        }

        let item = LibraryItem(
            documentId: documentId,
            source: source,
            title: "\(title) (Summary)",
            author: nil,
            wordCount: text.split(separator: " ").count,
            downloadState: .downloaded
        )
        appState.addItem(item)

        // Build a minimal CanonicalDocumentPackages from the summary text
        loadingTask?.cancel()
        loadingTask = Task {
            let packages = buildSyntheticPackages(text: text, title: title, documentId: documentId)

            // Finalize previous session
            finalizeCurrentSession()

            let vm = ReadingViewModel()
            self.viewModel = vm
            self.activeItem = item
            self.canonicalPackages = packages
            self.speedCleanPackage = nil
            self.speedCleanStatus = .notStarted
            self.isPolishingText = false
            self.activeLoadingPhase = nil
            self.backgroundActivityPhase = nil
            self.clearCompletionBanner()
            self.currentSource = .web(.init(url: URL(string: "about:blank")!))
            self.unitIDByChapterID = [:]
            self.prefetchedUnitIDs = []
            self.coverImageData = nil
            self.presentationState = .expanded

            let tracker = ReadingMetricsTracker(
                documentId: documentId,
                startTokenIndex: 0,
                readingMode: appState.settings.defaultReadingMode
            )
            self.metricsTracker = tracker
            vm.metricsTracker = tracker

            let readerDocument = CanonicalDocumentAdapter.buildReaderDocument(
                from: packages,
                source: .web(.init(url: URL(string: "about:blank")!)),
                ingestionVersion: DocumentIngestionService.currentIngestionVersion
            )

            vm.loadContent(
                tokens: readerDocument.tokens,
                chapters: readerDocument.chapters,
                blocks: readerDocument.blocks,
                startTokenIndex: 0
            )

            vm.wordsPerMinute = appState.settings.defaultWPM
            vm.setSoftStartPercentage(appState.settings.softStartPercentage)
            vm.setParagraphBreathMs(appState.settings.paragraphBreathMs)
            vm.readingMode = appState.settings.defaultReadingMode

            if vm.readingMode == .stream {
                vm.initializeStreamMode()
            }
        }
    }

    private func buildSyntheticPackages(text: String, title: String, documentId: UUID) -> CanonicalDocumentPackages {
        let unit = ReadingUnit(id: "summary", title: title, kind: .article, order: 0)
        let segment = ContentSegment(
            id: "segment-0",
            unitID: "summary",
            anchorID: "anchor-0",
            kind: .paragraphGroup,
            order: 0,
            text: text,
            textRange: TextRange(start: 0, end: text.count)
        )
        let anchor = AnchorRecord(id: "anchor-0", unitID: "summary", progress: 0, segmentID: "segment-0")

        let textAnchors = TextAnchorsPackage(
            plainText: text,
            units: [unit],
            segments: [segment],
            anchors: [anchor],
            parserVersion: 2,
            normalizerVersion: 1,
            segmenterVersion: 1
        )

        let manifest = DocumentManifest(
            id: documentId,
            title: title,
            authors: [],
            languageCode: nil,
            identifiers: [],
            documentType: .web,
            parserVersion: 2,
            normalizerVersion: 1,
            segmenterVersion: 1
        )

        let renderPackage = RenderPackage(
            format: .html,
            baseURL: URL(string: "reader-resource://\(documentId.uuidString)/")!,
            units: [RenderUnit(unitID: "summary", entryPath: "index.html", title: title)]
        )

        return CanonicalDocumentPackages(
            manifest: manifest,
            renderPackage: renderPackage,
            textAnchorsPackage: textAnchors
        )
    }

    // MARK: - Metrics

    private func finalizeCurrentSession() {
        guard let tracker = metricsTracker else { return }
        let record = tracker.finalize()
        self.metricsTracker = nil
        viewModel?.metricsTracker = nil

        syncService?.persistSession(record)
        Task {
            await syncService?.syncAll()
        }
    }
}
