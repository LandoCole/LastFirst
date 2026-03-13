import Foundation
import SwiftUI
import SwiftData

@MainActor
class ReaderCoordinator: ObservableObject {
    enum PresentationState: Equatable {
        case dismissed
        case expanded
        case minimized
    }

    @Published private(set) var viewModel: ReadingViewModel?
    @Published var presentationState: PresentationState = .dismissed
    @Published private(set) var activeItem: LibraryItem?
    @Published private(set) var canonicalPackages: CanonicalDocumentPackages?
    @Published private(set) var coverImageData: Data?
    @Published private(set) var isLoadingContent: Bool = false
    @Published var loadingError: String?

    private(set) var metricsTracker: ReadingMetricsTracker?
    private var loadingTask: Task<Void, Never>?
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
        viewModel = nil
        activeItem = nil
        canonicalPackages = nil
        coverImageData = nil
        presentationState = .dismissed
    }

    // MARK: - Content Loading

    private func loadContent(for item: LibraryItem, vm: ReadingViewModel, appState: AppState) async {
        vm.isLoading = true
        vm.loadingError = nil
        isLoadingContent = true

        do {
            let packages = try await loadOrIngestCanonicalPackages(item: item)
            self.canonicalPackages = packages

            let readerDocument = CanonicalDocumentAdapter.buildReaderDocument(
                from: packages,
                source: mapLibrarySource(item.source),
                ingestionVersion: DocumentIngestionService.currentIngestionVersion
            )

            vm.loadContent(
                tokens: readerDocument.tokens,
                chapters: readerDocument.chapters,
                blocks: readerDocument.blocks,
                startTokenIndex: item.progress.tokenIndex
            )

            vm.wordsPerMinute = appState.settings.defaultWPM
            vm.setSoftStartPercentage(appState.settings.softStartPercentage)
            vm.setParagraphBreathMs(appState.settings.paragraphBreathMs)
            vm.readingMode = appState.settings.defaultReadingMode

            if vm.readingMode == .stream {
                vm.initializeStreamMode()
            }

            if vm.words.isEmpty && vm.loadingError == nil {
                loadingError = "This book appears to be empty or could not be read."
            }

            // Persist word count on the library item
            if !vm.words.isEmpty, var updatedItem = self.activeItem {
                updatedItem.wordCount = vm.words.count
                self.activeItem = updatedItem
                appState.updateItem(updatedItem)
            }

            appState.populateFootnotes(from: packages, documentId: item.documentId)
            appState.loadPendingImages(for: item.documentId)

        } catch {
            vm.loadingError = error
            loadingError = error.localizedDescription
        }

        vm.isLoading = false
        isLoadingContent = false
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
