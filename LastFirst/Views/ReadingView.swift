import SwiftUI

struct ReadingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: ReadingViewModel

    let item: LibraryItem

    @State private var showImages: Bool = false
    @State private var showThemes: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    // Auto-hide dial state
    @State private var isDialHidden: Bool = false
    @State private var dialActivityTimer: Timer? = nil

    // Chapter swipe state
    @State private var chapterSwipeDragOffset: CGFloat = 0

    // Bottom bar tab state (replaces showBrowseView)
    enum BottomBarTab: Equatable {
        case none       // Normal spritz/stream view
        case browse     // ReaderScrollView
        case sparkle    // Placeholder view
        case bookmarks  // Inline bookmarks list
    }
    @State private var activeBottomTab: BottomBarTab = .none
    @State private var browseControlsVisible: Bool = true

    // Artifacts tab routing
    @State private var artifactsInitialTab: ArtifactsView.ArtifactTab? = nil

    // Hold-to-stream state
    @State private var holdStreamTimer: Timer? = nil

    // Search state
    @State private var showSearch: Bool = false
    @State private var searchMatchCount: Int = 0
    @State private var searchCurrentIndex: Int = 0
    @State private var tokenSearchResults: [SearchResult] = []

    // TOC state
    @State private var showTOC: Bool = false

    // Convenience: whether a bottom tab is active (dial/progress should collapse)
    private var isBottomTabActive: Bool {
        activeBottomTab != .none
    }

    var body: some View {
        GeometryReader { geometry in
            // Check if auto-hide applies (stream mode only)
            let autoHideApplies = viewModel.readingMode == .stream
            let effectivelyHidden = isDialHidden && autoHideApplies && appState.settings.autoHideDialDelay != .off

            let isSpritzMode = viewModel.readingMode == .spritz
            // Adjust reading area based on dial mode and auto-hide
            let readingAreaHeight: CGFloat = {
                if isBottomTabActive {
                    return geometry.size.height - 50 // minus bottom tab bar
                }
                if isSpritzMode {
                    return geometry.size.height * 0.60
                }
                // Stream mode
                if effectivelyHidden {
                    return geometry.size.height * 0.95
                }
                switch appState.settings.dialStyle {
                case .radial: return geometry.size.height * 0.48
                case .collapsed: return geometry.size.height * 0.85
                }
            }()

            ZStack {
                // Background - always use theme color
                resolvedTheme.backgroundColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Reading area
                    readingArea(geometry: geometry, height: readingAreaHeight)
                        .frame(height: readingAreaHeight)
                        .animation(.easeInOut(duration: 0.3), value: appState.settings.dialStyle)
                        .animation(.easeInOut(duration: 0.3), value: activeBottomTab)

                    Spacer()
                }

                // Gradient fades for browse/tab content modes
                if isBottomTabActive {
                    VStack {
                        // Top fade
                        LinearGradient(
                            colors: [resolvedTheme.backgroundColor, resolvedTheme.backgroundColor.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        .allowsHitTesting(false)

                        Spacer()

                        // Bottom fade (above tab bar)
                        LinearGradient(
                            colors: [resolvedTheme.backgroundColor.opacity(0), resolvedTheme.backgroundColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        .padding(.bottom, 50) // tab bar height
                        .allowsHitTesting(false)
                    }
                    .ignoresSafeArea(edges: .top)
                }

                // Dial + progress at bottom (slides down when bottom tab is active)
                VStack(spacing: 0) {
                    Spacer()

                    ProgressScrubber(viewModel: viewModel, theme: resolvedTheme)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 2)

                    // More menu row — below progress bar, left-aligned
                    HStack {
                        moreMenuButton
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 4)

                    LiquidGlassSpeedDial(
                        wpm: $viewModel.wordsPerMinute,
                        isPlaying: $viewModel.isPlaying,
                        controlColor: resolvedTheme.secondaryTextColor,
                        onPlayPauseToggle: {
                            viewModel.togglePlayPause()
                        },
                        onRewind: {
                            viewModel.rewindToSentenceStart()
                        },
                        onForwardSentence: {
                            viewModel.forwardToNextSentenceEnd()
                        },
                        onAddBookmark: {
                            quickSaveBookmark()
                        },
                        onHoldRewind: {
                            startHoldStream(forward: false)
                        },
                        onHoldForward: {
                            startHoldStream(forward: true)
                        },
                        onHoldRelease: {
                            stopHoldStream()
                        }
                    )
                    .padding(.bottom, 52) // Clear the bottom tab bar
                }
                .offset(y: isBottomTabActive ? 300 : 0)
                .opacity(isBottomTabActive ? 0 : (effectivelyHidden ? 0 : 1))
                .allowsHitTesting(!isBottomTabActive && !effectivelyHidden)

                // Bookmark creation overlay
                if viewModel.isCreatingBookmark {
                    bookmarkCreationOverlay
                }
            }
            .overlay(alignment: .bottom) {
                bottomTabBar
            }
        }
        .onChange(of: appState.settings.paragraphBreathMs) { _, newValue in
            viewModel.setParagraphBreathMs(newValue)
        }
        .onDisappear {
            dialActivityTimer?.invalidate()
            stopHoldStream()
        }
        .onChange(of: viewModel.wordsPerMinute) { _, _ in
            resetDialActivityTimer()
        }
        .onChange(of: appState.settings.autoHideDialDelay) { _, _ in
            resetDialActivityTimer()
        }
        .onChange(of: viewModel.readingMode) { _, newMode in
            resetDialActivityTimer()
            withAnimation(.easeInOut(duration: 0.2)) {
                activeBottomTab = .none
            }
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            if isPlaying {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeBottomTab = .none
                }
            }
        }
        .onChange(of: activeBottomTab) { _, newValue in
            if newValue != .browse {
                browseControlsVisible = true
            }
        }
        .onChange(of: appState.settings.dialStyle) { _, newStyle in
            if newStyle == .collapsed {
                withAnimation {
                    isDialHidden = false
                }
                dialActivityTimer?.invalidate()
                dialActivityTimer = nil
            }
        }
        .sheet(isPresented: $showImages) {
            ArtifactsView(
                documentId: item.documentId,
                initialTab: artifactsInitialTab,
                onNavigateToBookmark: { annotation in
                    viewModel.goToTokenIndex(annotation.range.start.tokenIndex)
                }
            )
        }
        .onChange(of: showImages) { _, isShowing in
            if !isShowing {
                artifactsInitialTab = nil
            }
        }
        .sheet(isPresented: $showThemes) {
            ThemesSettingsView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .preferredColorScheme(appState.settings.appearanceMode.preferredColorScheme)
        }
        .sheet(isPresented: $showTOC) {
            TOCSheetView(
                tocEntries: [],
                chapters: viewModel.chapters,
                currentChapterTitle: currentChapterTitle,
                pageList: readerCoordinator.canonicalPackages?.textAnchorsPackage.pageList ?? [],
                onNavigate: { chapter in
                    viewModel.goToChapter(chapter)
                }
            )
        }
        .alert("Error Loading Book", isPresented: $showErrorAlert) {
            Button("OK") {
                showErrorAlert = false
            }
            Button("Return to Library") {
                showErrorAlert = false
                readerCoordinator.dismiss(appState: appState)
            }
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if viewModel.isLoading {
                loadingOverlay
            }
        }
        .overlay {
            Color.black
                .opacity(max(0, min(1, 1 - appState.settings.readerBrightness)))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheetView(
                isPresented: $showSearch,
                onSearch: { query in
                    performSearch(query: query)
                },
                tokenResults: tokenSearchResults,
                onResultTapped: { result in
                    viewModel.goToWord(at: result.wordIndex)
                }
            )
            .presentationDragIndicator(.visible)
        }
        .onChange(of: showSearch) { _, isShowing in
            if !isShowing {
                tokenSearchResults = []
                searchMatchCount = 0
                searchCurrentIndex = 0
            }
        }
    }

    private var resolvedTheme: ResolvedReaderTheme {
        let clampedFont = min(
            max(appState.settings.fontSize, ReaderThemeSettings.minFontSize),
            ReaderThemeSettings.maxFontSize
        )
        return appState.settings.readerThemeSettings.resolvedTheme(
            appearanceMode: appState.settings.appearanceMode,
            systemScheme: colorScheme,
            fontSize: clampedFont
        )
    }

    // MARK: - Bottom Tab Bar
    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            bottomTabButton(systemName: "text.justify.left", tab: .browse)
            bottomTabButton(systemName: "sparkles", tab: .sparkle)
            bottomTabButton(systemName: "bookmark.fill", tab: .bookmarks)
        }
        .frame(height: 50)
        .background(
            resolvedTheme.backgroundColor.opacity(0.95)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func bottomTabButton(systemName: String, tab: BottomBarTab) -> some View {
        let isActive = activeBottomTab == tab
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                if activeBottomTab == tab {
                    activeBottomTab = .none
                } else {
                    activeBottomTab = tab
                }
            }
        }) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? .primary : .secondary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Loading book...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func quickSaveBookmark() {
        guard let draft = viewModel.quickBookmarkDraft() else { return }

        let range = AnnotationRange(
            start: DocumentAnchor(tokenIndex: draft.startTokenIndex, location: nil),
            end: DocumentAnchor(tokenIndex: draft.endTokenIndex, location: nil)
        )

        let annotation = Annotation(
            documentId: item.documentId,
            kind: .bookmark,
            range: range,
            excerpt: draft.text
        )

        appState.addAnnotation(annotation)
    }

    // MARK: - Auto-Hide Dial Timer
    private func resetDialActivityTimer() {
        dialActivityTimer?.invalidate()
        dialActivityTimer = nil

        if isDialHidden {
            withAnimation {
                isDialHidden = false
            }
        }

        guard appState.settings.dialStyle != .collapsed,
              let delay = appState.settings.autoHideDialDelay.seconds,
              viewModel.readingMode == .stream else {
            return
        }

        dialActivityTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                withAnimation {
                    isDialHidden = true
                }
            }
        }
    }

    // MARK: - More Menu Button

    private var moreMenuButton: some View {
        Menu {
            Button(action: { showSearch = true }) {
                Label("Search", systemImage: "magnifyingglass")
            }
            Button(action: { showTOC = true }) {
                Label("Table of Contents", systemImage: "list.bullet")
            }
            Button(action: { showThemes = true }) {
                Label("Themes", systemImage: "paintbrush")
            }

            Divider()

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.readingMode = .spritz
                }
            }) {
                HStack {
                    Text("Spritz")
                    if viewModel.readingMode == .spritz {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.readingMode = .stream
                }
            }) {
                HStack {
                    Text("Stream")
                    if viewModel.readingMode == .stream {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(resolvedTheme.secondaryTextColor)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hold-to-Stream

    private func startHoldStream(forward: Bool) {
        stopHoldStream()
        viewModel.pause()
        let interval = 60.0 / Double(viewModel.wordsPerMinute)
        holdStreamTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                if forward {
                    viewModel.advanceOneWord()
                } else {
                    viewModel.rewindOneWord()
                }
            }
        }
    }

    private func stopHoldStream() {
        holdStreamTimer?.invalidate()
        holdStreamTimer = nil
    }

    // MARK: - Reading Area
    @ViewBuilder
    private func readingArea(geometry: GeometryProxy, height: CGFloat) -> some View {
        ZStack {
            Group {
                switch activeBottomTab {
                case .browse:
                    // Browse mode via bottom tab
                    ReaderScrollView(
                        viewModel: viewModel,
                        fontSize: max(14, resolvedTheme.fontSize - 8),
                        topContentInset: 16,
                        theme: resolvedTheme,
                        onWordTapped: { index in
                            viewModel.goToWord(at: index)
                        },
                        onScrollDirectionHide: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                browseControlsVisible = false
                            }
                        },
                        onScrollDirectionShow: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                browseControlsVisible = true
                            }
                        },
                        browseControlsVisible: browseControlsVisible
                    )
                    .transition(.opacity)

                case .sparkle:
                    // Placeholder sparkle view
                    VStack {
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Coming soon")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)

                case .bookmarks:
                    // Inline bookmarks list
                    inlineBookmarksView
                        .transition(.opacity)

                case .none:
                    // Normal reading modes
                    switch viewModel.readingMode {
                    case .spritz:
                        SpritzModeView(
                            viewModel: viewModel,
                            theme: resolvedTheme
                        )
                    case .stream:
                        StreamModeView(
                            viewModel: viewModel,
                            theme: resolvedTheme,
                            screenWidth: geometry.size.width,
                            availableHeight: height
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, activeBottomTab == .browse ? 0 : 24)

            if activeBottomTab == .none, let titleCard = viewModel.activeTitleCard {
                VStack(spacing: 16) {
                    Spacer()

                    VStack(spacing: 12) {
                        Text(titleCard.title)
                            .font(.system(size: min(48, appState.settings.fontSize + 6), weight: .semibold, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        if let subtitle = titleCard.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: appState.settings.fontSize, weight: .regular, design: .serif))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }

                        if let epigraph = titleCard.epigraph, !epigraph.isEmpty {
                            Text(epigraph)
                                .font(.system(size: appState.settings.fontSize - 2, weight: .regular, design: .serif))
                                .multilineTextAlignment(.leading)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)

                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .offset(x: chapterSwipeDragOffset)
        .gesture(
            activeBottomTab == .none ?
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    chapterSwipeDragOffset = value.translation.width * 0.4
                }
                .onEnded { value in
                    let threshold: CGFloat = 80
                    let horizontalAmount = value.translation.width

                    guard abs(horizontalAmount) > abs(value.translation.height) else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            chapterSwipeDragOffset = 0
                        }
                        return
                    }

                    if horizontalAmount < -threshold {
                        // Swipe left -> next chapter
                        navigateChapter(direction: 1)
                    } else if horizontalAmount > threshold {
                        // Swipe right -> previous chapter
                        navigateChapter(direction: -1)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            chapterSwipeDragOffset = 0
                        }
                    }
                }
            : nil
        )
    }

    private func navigateChapter(direction: Int) {
        let screenWidth = UIScreen.main.bounds.width

        withAnimation(.easeIn(duration: 0.15)) {
            chapterSwipeDragOffset = -CGFloat(direction) * screenWidth * 0.6
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if direction > 0 {
                viewModel.goToNextChapter()
            } else {
                viewModel.goToPreviousChapter()
            }

            chapterSwipeDragOffset = CGFloat(direction) * screenWidth * 0.6

            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                chapterSwipeDragOffset = 0
            }
        }
    }

    // MARK: - Inline Bookmarks View
    private var inlineBookmarksView: some View {
        let bookmarks = appState
            .getAnnotations(for: item.documentId)
            .filter { $0.kind == .bookmark }
            .sorted { $0.createdAt > $1.createdAt }

        return Group {
            if bookmarks.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "bookmark")
                        .font(.system(size: 48))
                        .foregroundColor(resolvedTheme.secondaryTextColor.opacity(0.4))
                    Text("No Bookmarks")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(resolvedTheme.textColor)
                    Text("Long-press the dial to save a bookmark")
                        .font(.subheadline)
                        .foregroundColor(resolvedTheme.secondaryTextColor)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bookmarks) { bookmark in
                            Button(action: {
                                // Navigate to bookmark position via browse mode
                                viewModel.goToTokenIndex(bookmark.range.start.tokenIndex)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    activeBottomTab = .browse
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let title = bookmark.title {
                                        Text(title)
                                            .font(.headline)
                                            .foregroundColor(resolvedTheme.textColor)
                                    }

                                    Text(bookmark.excerpt ?? "")
                                        .font(.subheadline)
                                        .foregroundColor(resolvedTheme.secondaryTextColor)
                                        .lineLimit(3)

                                    HStack {
                                        Text(bookmark.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundColor(resolvedTheme.secondaryTextColor.opacity(0.7))

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(resolvedTheme.secondaryTextColor.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.horizontal, 24)
                                .opacity(0.3)
                        }
                    }
                    .padding(.bottom, 60) // Room for bottom tab bar
                }
            }
        }
    }

    // MARK: - Bookmark Creation Overlay
    private var bookmarkCreationOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.cancelBookmarkCreation()
                }

            VStack(spacing: 20) {
                Text("Save Bookmark")
                    .font(.headline)

                ScrollView {
                    Text(viewModel.getBookmarkText())
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.3))
                )
                .padding(.horizontal)

                HStack(spacing: 20) {
                    Button("Cancel") {
                        viewModel.cancelBookmarkCreation()
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                    Button("Save") {
                        let start = viewModel.bookmarkStartIndex
                        let end = viewModel.bookmarkEndIndex
                        let excerpt = viewModel.getBookmarkText()

                        let range = AnnotationRange(
                            start: DocumentAnchor(tokenIndex: start, location: nil),
                            end: DocumentAnchor(tokenIndex: end, location: nil)
                        )

                        let annotation = Annotation(
                            documentId: item.documentId,
                            kind: .bookmark,
                            range: range,
                            excerpt: excerpt
                        )

                        appState.addAnnotation(annotation)
                        viewModel.cancelBookmarkCreation()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primary)
                    .cornerRadius(8)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.systemBackground))
            )
            .padding(32)
        }
    }

    private var currentChapterTitle: String? {
        guard !viewModel.chapters.isEmpty else { return nil }
        return viewModel.chapters.last(where: { $0.startWordIndex <= viewModel.currentWordIndex })?.title
    }

    private func performSearch(query: String) {
        let results = FullTextSearchService.search(
            query: query,
            words: viewModel.words,
            chapters: viewModel.chapters
        )
        tokenSearchResults = results
        searchMatchCount = results.count
        searchCurrentIndex = 0
    }

}

// MARK: - Curved Line Shape
struct CurvedLine: Shape {
    var curveAmount: CGFloat

    var animatableData: CGFloat {
        get { curveAmount }
        set { curveAmount = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startPoint = CGPoint(x: rect.minX, y: rect.midY)
        let endPoint = CGPoint(x: rect.maxX, y: rect.midY)
        let controlPoint = CGPoint(x: rect.midX, y: rect.midY + curveAmount)

        path.move(to: startPoint)
        path.addQuadCurve(to: endPoint, control: controlPoint)

        return path
    }
}

#if DEBUG
struct ReadingView_Previews: PreviewProvider {
    static var previews: some View {
        ReadingView(
            viewModel: ReadingViewModel(),
            item: LibraryItem(
                documentId: UUID(),
                source: .localFile(.init(fileURL: URL(fileURLWithPath: "/dev/null"), fileType: .epub)),
                title: "Sample Book",
                author: "Test Author"
            )
        )
        .environmentObject(AppState())
        .environmentObject(ReaderCoordinator())
    }
}
#endif
