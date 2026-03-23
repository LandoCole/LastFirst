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
        case sparkle    // AI features menu
        case bookmarks  // Inline bookmarks list
    }
    @State private var activeBottomTab: BottomBarTab = .none
    @State private var browseControlsVisible: Bool = true

    // AI text mode state
    @State private var activeAIMode: AITextMode = .original
    @State private var processingAIMode: AITextMode? = nil
    @State private var readyAIModes: Set<AITextMode> = []

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
    @State private var pendingPolishChapter: Chapter?
    @State private var showPolishDialog: Bool = false

    init(viewModel: ReadingViewModel, item: LibraryItem) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.item = item
    }

    // Convenience: whether a bottom tab is active (dial/progress should collapse)
    private var isBottomTabActive: Bool {
        activeBottomTab != .none
    }

    private var topSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
            let window = windowScene.windows.first else { return 59 }
        return window.safeAreaInsets.top
    }

    private var presentationVerticalOffset: CGFloat {
        -24
    }

    private var baseContent: AnyView {
        AnyView(
            GeometryReader { geometry in
                mainContent(geometry: geometry)
            }
            .offset(y: presentationVerticalOffset)
        )
    }

    private var interactionContent: AnyView {
        AnyView(
            baseContent
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
                .onChange(of: viewModel.readingMode) { _, _ in
                    resetDialActivityTimer()
                    if processingAIMode == nil {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeBottomTab = .none
                        }
                    }
                }
                .onChange(of: viewModel.isPlaying) { _, isPlaying in
                    if isPlaying && processingAIMode == nil {
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
        )
    }

    private var presentationContent: AnyView {
        AnyView(
            interactionContent
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
                        .preferredColorScheme(appState.settings.appearanceMode.preferredColorScheme)
                }
                .sheet(isPresented: $showTOC) {
                    TOCSheetView(
                        tocEntries: [],
                        chapters: viewModel.chapters,
                        currentChapterTitle: currentChapterTitle,
                        pageList: readerCoordinator.canonicalPackages?.textAnchorsPackage.pageList ?? [],
                        onNavigate: { chapter in
                            handleChapterSelection(chapter)
                        }
                    )
                }
        )
    }

    private var dialogContent: AnyView {
        AnyView(
            presentationContent
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
                .confirmationDialog(
                    "This chapter can be polished for a smoother speed-reading experience.",
                    isPresented: $showPolishDialog,
                    titleVisibility: .visible,
                    presenting: pendingPolishChapter
                ) { chapter in
                    Button("Read Now") {
                        viewModel.goToChapter(chapter)
                        pendingPolishChapter = nil
                    }
                    Button("Polish Up, Read in a Few") {
                        Task {
                            await readerCoordinator.polishChapterAndNavigate(chapter, appState: appState)
                            pendingPolishChapter = nil
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        pendingPolishChapter = nil
                    }
                } message: { _ in
                    Text("Polish Up improves pacing and readability for speed reading without changing the meaning.")
                }
        )
    }

    private var decoratedContent: AnyView {
        AnyView(
            dialogContent
                .overlay {
                    if readerCoordinator.isLoadingContent || readerCoordinator.isPolishingText {
                        loadingOverlay
                    }
                }
                .overlay(alignment: .top) {
                    speedCleanStatusBanner
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
        )
    }

    var body: some View {
        decoratedContent
    }

    private func mainContent(geometry: GeometryProxy) -> some View {
        let autoHideApplies = viewModel.readingMode == .stream
        let effectivelyHidden = isDialHidden && autoHideApplies && appState.settings.autoHideDialDelay != .off
        let isSpritzMode = viewModel.readingMode == .spritz
        let readingAreaHeight = currentReadingAreaHeight(
            geometry: geometry,
            isSpritzMode: isSpritzMode,
            effectivelyHidden: effectivelyHidden
        )

        return ZStack {
            resolvedTheme.backgroundColor
                .ignoresSafeArea()

            ThemePatternOverlay(
                pattern: staticOverlayPattern,
                variant: resolvedTheme.variant,
                compact: false
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                readingArea(geometry: geometry, height: readingAreaHeight)
                    .frame(height: readingAreaHeight)
                    .animation(.easeInOut(duration: 0.3), value: appState.settings.dialStyle)
                    .animation(.easeInOut(duration: 0.3), value: activeBottomTab)

                Spacer()
            }

            if isBottomTabActive {
                let bgColor = resolvedTheme.backgroundColor
                VStack {
                    LinearGradient(
                        colors: [bgColor, bgColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .allowsHitTesting(false)

                    Spacer()

                    LinearGradient(
                        colors: [bgColor.opacity(0), bgColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .padding(.bottom, 50)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea(edges: .top)
            }

            VStack(spacing: 0) {
                Spacer()

                ProgressScrubber(viewModel: viewModel, theme: resolvedTheme)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 2)

                HStack {
                    readerControlsMenu
                    Spacer()
                    contentExploreMenu
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
                .padding(.bottom, 52)
            }
            .offset(y: isBottomTabActive ? 300 : 0)
            .opacity(isBottomTabActive ? 0 : (effectivelyHidden ? 0 : 1))
            .allowsHitTesting(!isBottomTabActive && !effectivelyHidden)

            if viewModel.isCreatingBookmark {
                bookmarkCreationOverlay
            }
        }
        .overlay(alignment: .bottom) {
            bottomTabBar
        }
    }

    private func currentReadingAreaHeight(
        geometry: GeometryProxy,
        isSpritzMode: Bool,
        effectivelyHidden: Bool
    ) -> CGFloat {
        if isBottomTabActive {
            return geometry.size.height - 50
        }
        if isSpritzMode {
            return geometry.size.height * 0.60
        }
        if effectivelyHidden {
            return geometry.size.height * 0.95
        }
        switch appState.settings.dialStyle {
        case .radial:
            return geometry.size.height * 0.48
        case .collapsed:
            return geometry.size.height * 0.85
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

    /// Pattern to use for the static (non-scrolling) overlay.
    /// Ruled patterns are rendered inside their own content views for all modes
    /// (stream, browse, spritz); only use static overlay for non-ruled patterns.
    private var staticOverlayPattern: ReaderBackgroundPattern {
        let pattern = resolvedTheme.definition.pattern
        guard !pattern.hasRuledLines else { return .none }
        return pattern
    }

    /// Horizontal padding for the reading area content.
    /// Browse mode: 0 (ReaderScrollView handles its own padding).
    /// Stream/spritz mode with ruled lines: 0 (they handle their own padding/background).
    /// Otherwise: 24pt default.
    private var streamModePaddingValue: CGFloat {
        if activeBottomTab == .browse { return 0 }
        if activeBottomTab == .none && resolvedTheme.definition.pattern.hasRuledLines {
            return 0
        }
        return 24
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
        let isLocked = processingAIMode != nil
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
                .foregroundColor(isActive ? resolvedTheme.textColor : resolvedTheme.secondaryTextColor.opacity(isLocked && !isActive ? 0.2 : 0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.plain)
        .disabled(isLocked && !isActive)
    }

    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.warmBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(readerCoordinator.loadingOverlayText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var speedCleanStatusBanner: some View {
        Group {
            if let bannerText = speedCleanBannerText {
                Text(bannerText)
                    .font(.caption.weight(.medium))
                    .foregroundColor(resolvedTheme.textColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 16)
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

    // MARK: - Reader Controls Menu (Left — slider icon)

    private var readerControlsMenu: some View {
        Menu {
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

            if readerCoordinator.speedCleanPackage != nil {
                Divider()

                Button(action: {
                    readerCoordinator.revertToOriginal(appState: appState)
                }) {
                    HStack {
                        Text("Original")
                        if readerCoordinator.activeVariant == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button(action: {
                    readerCoordinator.toggleSpeedClean(appState: appState)
                }) {
                    HStack {
                        Text("Optimized")
                        if readerCoordinator.activeVariant?.kind == .speedClean {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button(action: { showThemes = true }) {
                Label("Themes", systemImage: "paintbrush")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(resolvedTheme.secondaryTextColor)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Explore Menu (Right — ellipsis icon)

    private var contentExploreMenu: some View {
        Menu {
            Button(action: { showSearch = true }) {
                Label("Search", systemImage: "magnifyingglass")
            }
            Button(action: { showTOC = true }) {
                Label("Table of Contents", systemImage: "list.bullet")
            }

            if let sourceUrl = itemSourceURL {
                Link(destination: sourceUrl) {
                    Label(sourceUrl.host ?? "View Source", systemImage: "safari")
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

    private var itemSourceURL: URL? {
        switch item.source {
        case .web(let web):
            return web.url.absoluteString == "about:blank" ? nil : web.url
        case .curated(let curated):
            return curated.sourceUrl
        default:
            return nil
        }
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
                    AIFeaturesMenuView(
                        theme: resolvedTheme,
                        bookTitle: item.title,
                        chapterTitle: viewModel.currentChapter?.title ?? "",
                        progressPercent: Int(item.progress.percentComplete),
                        activeMode: activeAIMode,
                        processingMode: processingAIMode,
                        readyModes: readyAIModes,
                        onSelectMode: { mode, scope in handleAITextModeSelection(mode, scope: scope) },
                        onRecapSession: { handleRecapSession() }
                    )
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
            .padding(.top, topSafeArea + 48)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, streamModePaddingValue)

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
        guard let targetChapter = chapterForNavigation(direction: direction) else { return }
        guard !readerCoordinator.shouldPromptForPolish(targetChapter) else {
            pendingPolishChapter = targetChapter
            showPolishDialog = true
            return
        }

        let screenWidth = UIScreen.main.bounds.width

        withAnimation(.easeIn(duration: 0.15)) {
            chapterSwipeDragOffset = -CGFloat(direction) * screenWidth * 0.6
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            viewModel.goToChapter(targetChapter)

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
                    .fill(Color.warmBackground)
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

    private var speedCleanBannerText: String? {
        readerCoordinator.speedCleanBannerText
    }

    private func handleChapterSelection(_ chapter: Chapter) {
        if readerCoordinator.shouldPromptForPolish(chapter) {
            pendingPolishChapter = chapter
            showPolishDialog = true
            return
        }

        viewModel.goToChapter(chapter)
    }

    private func chapterForNavigation(direction: Int) -> Chapter? {
        guard !viewModel.chapters.isEmpty else { return nil }
        let currentIndex = viewModel.currentChapterIndex

        if direction > 0 {
            let nextIndex = currentIndex + 1
            guard nextIndex < viewModel.chapters.count else { return nil }
            return viewModel.chapters[nextIndex]
        }

        if currentIndex >= 0 && currentIndex < viewModel.chapters.count {
            let currentChapter = viewModel.chapters[currentIndex]
            if viewModel.currentWordIndex > currentChapter.startWordIndex + 5 {
                return currentChapter
            }
        }

        let previousIndex = currentIndex - 1
        guard previousIndex >= 0, previousIndex < viewModel.chapters.count else { return nil }
        return viewModel.chapters[previousIndex]
    }

    // MARK: - AI Text Mode Handlers

    private func handleAITextModeSelection(_ mode: AITextMode, scope: SummaryScope?) {
        switch mode {
        case .original:
            readerCoordinator.revertToOriginal(appState: appState)
            activeAIMode = .original

        case .optimized:
            if readyAIModes.contains(.optimized) || readerCoordinator.speedCleanPackage != nil {
                readerCoordinator.toggleSpeedClean(appState: appState)
                activeAIMode = (activeAIMode == .optimized) ? .original : .optimized
                readyAIModes.insert(.optimized)
            } else {
                readerCoordinator.toggleSpeedClean(appState: appState)
                activeAIMode = .optimized
                readyAIModes.insert(.optimized)
            }

        case .easyRead:
            Task {
                if let existing = await findExistingVariant(named: "Easy Read") {
                    applyExistingVariant(existing)
                    activeAIMode = .easyRead
                    readyAIModes.insert(.easyRead)
                } else {
                    processCustomVariant(mode: .easyRead, scope: .chapter)
                }
            }

        case .quickSummary:
            let resolvedScope = scope ?? .chapter
            Task {
                if resolvedScope == .chapter, let existing = await findExistingVariant(named: "Quick Summary") {
                    applyExistingVariant(existing)
                    activeAIMode = .quickSummary
                    readyAIModes.insert(.quickSummary)
                } else {
                    processCustomVariant(mode: .quickSummary, scope: resolvedScope)
                }
            }
        }
    }

    private func findExistingVariant(named name: String) async -> TextVariant? {
        guard let chapter = viewModel.currentChapter,
              let unitID = readerCoordinator.unitIDForChapter(chapter) else { return nil }

        // Layer 1: In-memory
        if let package = readerCoordinator.loadedTextVariantPackage,
           let match = package.variants.first(where: { $0.name == name && $0.unitID == unitID && $0.status == .ready }) {
            return match
        }

        // Layer 2 & 3: Local disk, then Supabase (handled inside loadVariants)
        if let package = await TextVariantService.shared.loadVariants(documentId: item.documentId) {
            await MainActor.run {
                readerCoordinator.loadedTextVariantPackage = package
            }
            return package.variants.first { $0.name == name && $0.unitID == unitID && $0.status == .ready }
        }

        return nil
    }

    private func applyExistingVariant(_ variant: TextVariant) {
        guard let canonicalPackages = readerCoordinator.canonicalPackages else { return }
        Task {
            let modifiedPackages = await TextVariantService.shared.apply(variant: variant, to: canonicalPackages)
            await MainActor.run {
                readerCoordinator.applyVariant(variant, modifiedPackages: modifiedPackages, appState: appState)
            }
        }
    }

    private func processCustomVariant(mode: AITextMode, scope: SummaryScope) {
        processingAIMode = mode
        Task {
            let instructions = mode == .easyRead
                ? "Rewrite this text in clear, approachable, plain language. Preserve the original meaning and approximately the same length. Do not summarize or condense."
                : "Condense this to exactly what the reader needs to know. Be concise and easily digestible. Preserve key facts and meaning."

            if scope == .entireBook {
                await processAllUnits(instructions: instructions, modeName: mode.title)
            } else {
                await processCurrentUnit(instructions: instructions, modeName: mode.title)
            }

            await MainActor.run {
                processingAIMode = nil
                activeAIMode = mode
                readyAIModes.insert(mode)
            }
        }
    }

    private func processCurrentUnit(instructions: String, modeName: String) async {
        guard let chapter = viewModel.currentChapter,
              let unitID = readerCoordinator.unitIDForChapter(chapter),
              let canonicalPackages = readerCoordinator.canonicalPackages,
              let source = readerCoordinator.currentSource else { return }

        let variant = await TextVariantService.shared.createVariant(
            documentId: item.documentId,
            unitID: unitID,
            kind: .custom,
            name: modeName,
            instructions: instructions,
            conciseness: nil,
            canonicalPackages: canonicalPackages,
            source: source
        )

        guard variant.status == .ready else { return }

        let modifiedPackages = await TextVariantService.shared.apply(variant: variant, to: canonicalPackages)
        await MainActor.run {
            readerCoordinator.applyVariant(variant, modifiedPackages: modifiedPackages, appState: appState)
            readerCoordinator.loadedTextVariantPackage = readerCoordinator.loadedTextVariantPackage ?? TextVariantPackage(documentId: item.documentId)
            readerCoordinator.loadedTextVariantPackage?.variants.append(variant)
        }
    }

    private func processAllUnits(instructions: String, modeName: String) async {
        guard let canonicalPackages = readerCoordinator.canonicalPackages,
              let source = readerCoordinator.currentSource else { return }

        let units = canonicalPackages.textAnchorsPackage.units.sorted { $0.order < $1.order }
        var allVariants: [TextVariant] = []

        for unit in units {
            guard !Task.isCancelled else { return }

            let variant = await TextVariantService.shared.createVariant(
                documentId: item.documentId,
                unitID: unit.id,
                kind: .custom,
                name: modeName,
                instructions: instructions,
                conciseness: nil,
                canonicalPackages: canonicalPackages,
                source: source
            )
            allVariants.append(variant)
        }

        // Apply all variants by composing them onto canonical packages
        var composedPackages = canonicalPackages
        for variant in allVariants where variant.status == .ready {
            composedPackages = await TextVariantService.shared.apply(variant: variant, to: composedPackages)
        }

        if let firstVariant = allVariants.first(where: { $0.status == .ready }) {
            await MainActor.run {
                readerCoordinator.applyVariant(firstVariant, modifiedPackages: composedPackages, appState: appState)
            }
        }
    }

    // MARK: - Recap Session

    private func handleRecapSession() {
        let bookTitle = item.title
        let chapter = viewModel.currentChapter?.title ?? "current chapter"
        let progress = Int(item.progress.percentComplete)
        let recentWords = Array(viewModel.words.suffix(500)).joined(separator: " ")

        let context = """
        I've been reading "\(bookTitle)". I'm currently at \(chapter) (\(progress)% through).
        Here's what I recently read: \(recentWords)
        Give me a recap of what's happened and where I am in the story.
        """

        appState.pendingCuratorContext = context
        readerCoordinator.minimize()
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
