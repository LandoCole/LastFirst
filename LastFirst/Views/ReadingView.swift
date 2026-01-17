import SwiftUI

struct ReadingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ReadingViewModel()

    let book: Book
    
    private let parser = DocumentParser()

    @State private var showLibrary: Bool = false
    @State private var showSettings: Bool = false
    @State private var showBookmarks: Bool = false
    @State private var showImages: Bool = false
    @State private var showPausedScroll: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    // Dial transition state
    @State private var dialTransitionProgress: CGFloat = 0
    @State private var handleDragOffset: CGFloat = 0
    
    // Auto-hide dial state
    @State private var isDialHidden: Bool = false
    @State private var dialActivityTimer: Timer? = nil

    var body: some View {
        GeometryReader { geometry in
            // Check if auto-hide applies (stream/scan modes only)
            let autoHideApplies = viewModel.readingMode == .stream || viewModel.readingMode == .scan
            let effectivelyHidden = isDialHidden && autoHideApplies && appState.settings.autoHideDialDelay != .off
            
            let dialHeight: CGFloat = appState.settings.dialStyle == .collapsed ? 50 : geometry.size.height * 0.25
            // Adjust reading area based on dial mode and auto-hide
            let readingAreaHeight: CGFloat = {
                if effectivelyHidden {
                    return geometry.size.height * 0.95
                }
                switch appState.settings.dialStyle {
                case .radial: return geometry.size.height * 0.48
                case .collapsed: return geometry.size.height * 0.85
                }
            }()

            ZStack {
                // Background
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar
                    topBar

                    // Reading area
                    readingArea(geometry: geometry, height: readingAreaHeight)
                        .frame(height: readingAreaHeight)
                        .animation(.easeInOut(duration: 0.3), value: appState.settings.dialStyle)

                    Spacer()
                }

                // Dial at bottom with buttons and handle above
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Only show buttons and handle when not collapsed
                    if appState.settings.dialStyle != .collapsed {
                        // Bookmark and images buttons above dial
                        HStack {
                            Button(action: { 
                                resetDialActivityTimer()
                                showBookmarks = true 
                            }) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 18))
                                    .foregroundColor(.primary)
                            }
                            .padding(.leading, 24)

                            Spacer()

                            Button(action: { 
                                resetDialActivityTimer()
                                showImages = true 
                            }) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "photo.stack")
                                        .font(.system(size: 18))
                                        .foregroundColor(.primary)

                                    let unseenCount = appState.getUnseenImageCount(for: book.id)
                                    if unseenCount > 0 {
                                        Text("\(unseenCount)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 16, height: 16)
                                            .background(Circle().fill(Color.red))
                                            .offset(x: 8, y: -8)
                                    }
                                }
                            }
                            .padding(.trailing, 24)
                        }
                        .padding(.bottom, appState.settings.dialStyle == .radial ? 70 : 8)
                        
                        // Drag handle for switching dial modes
                        dialSwitchHandle
                            .padding(.bottom, 4)
                    }
                    
                    dialView
                        .frame(height: dialHeight)
                }
                .offset(y: effectivelyHidden ? geometry.size.height * 0.20 : 0)
                .animation(.easeInOut(duration: 0.4), value: effectivelyHidden)
                .onTapGesture {
                    if effectivelyHidden {
                        withAnimation {
                            isDialHidden = false
                        }
                        resetDialActivityTimer()
                    }
                }

                // Bookmark creation overlay
                if viewModel.isCreatingBookmark {
                    bookmarkCreationOverlay
                }
            }
        }
        .onAppear {
            Task {
                await loadBookContent()
            }
        }
        .onDisappear {
            saveProgress()
            dialActivityTimer?.invalidate()
        }
        .onChange(of: viewModel.wordsPerMinute) { _, _ in
            resetDialActivityTimer()
        }
        .onChange(of: appState.settings.autoHideDialDelay) { _, _ in
            resetDialActivityTimer()
        }
        .onChange(of: viewModel.readingMode) { _, _ in
            resetDialActivityTimer()
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(bookId: book.id)
        }
        .sheet(isPresented: $showImages) {
            ArtifactsView(bookId: book.id)
        }
        .alert("Error Loading Book", isPresented: $showErrorAlert) {
            Button("OK") {
                showErrorAlert = false
            }
            Button("Return to Library") {
                showErrorAlert = false
                showLibrary = true
            }
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if viewModel.isLoading {
                loadingOverlay
            }
        }
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

    // MARK: - Dial Switch Handle
    private var dialSwitchHandle: some View {
        let isRadial = appState.settings.dialStyle == .radial
        // Curve downward (negative) for radial mode like an arch
        let curveAmount: CGFloat = isRadial ? -4 : 0
        let dragThreshold: CGFloat = 60
        
        return ZStack {
            // Curved/flat line that acts as drag handle
            CurvedLine(curveAmount: curveAmount + (isRadial ? handleDragOffset * 0.1 : 0))
                .stroke(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 50, height: 12)
        }
        .contentShape(Rectangle().size(width: 80, height: 30))
        .offset(y: handleDragOffset + (isRadial ? -40 : 0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Can only drag down when radial -> collapsed
                    if isRadial {
                        handleDragOffset = max(0, min(dragThreshold + 20, value.translation.height))
                    }
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        // Check if drag exceeded threshold
                        if isRadial && handleDragOffset > dragThreshold {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            appState.settings.dialStyle = .collapsed
                        }
                        handleDragOffset = 0
                    }
                }
        )
        .animation(.easeInOut(duration: 0.3), value: appState.settings.dialStyle)
    }
    
    // MARK: - Dial View
    @ViewBuilder
    private var dialView: some View {
        ZStack {
            // Radial dial
            SpeedDial(
                wpm: $viewModel.wordsPerMinute,
                isPlaying: $viewModel.isPlaying,
                isPushedDown: $viewModel.isDialPushedDown,
                onAddBookmark: {
                    quickSaveBookmark()
                },
                onPlayPauseToggle: {
                    viewModel.togglePlayPause()
                }
            )
            .scaleEffect(x: 1, y: appState.settings.dialStyle == .radial ? 1 : 0.01)
            .opacity(appState.settings.dialStyle == .radial ? 1 : 0)
            
            // Collapsed dial
            CollapsedDial(
                wpm: $viewModel.wordsPerMinute,
                isPlaying: $viewModel.isPlaying,
                isPushedDown: $viewModel.isDialPushedDown,
                onAddBookmark: {
                    quickSaveBookmark()
                },
                onPlayPauseToggle: {
                    viewModel.togglePlayPause()
                },
                onShowBookmarks: {
                    showBookmarks = true
                },
                onShowImages: {
                    showImages = true
                },
                unseenImageCount: appState.getUnseenImageCount(for: book.id)
            )
            .scaleEffect(x: 1, y: appState.settings.dialStyle == .collapsed ? 1 : 0.01)
            .opacity(appState.settings.dialStyle == .collapsed ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        // Swipe up to expand to radial
                        if value.translation.height < -40 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                appState.settings.dialStyle = .radial
                            }
                        }
                    }
            )
        }
        .animation(.easeInOut(duration: 0.4), value: appState.settings.dialStyle)
    }
    
    private func quickSaveBookmark() {
        if var bookmark = viewModel.quickBookmark() {
            bookmark = Bookmark(
                bookId: book.id,
                text: bookmark.text,
                startWordIndex: bookmark.startWordIndex,
                endWordIndex: bookmark.endWordIndex
            )
            appState.addBookmark(bookmark)
        }
    }
    
    // MARK: - Auto-Hide Dial Timer
    private func resetDialActivityTimer() {
        // Cancel existing timer
        dialActivityTimer?.invalidate()
        dialActivityTimer = nil
        
        // Show dial if hidden
        if isDialHidden {
            withAnimation {
                isDialHidden = false
            }
        }
        
        // Only set timer if auto-hide is enabled and in stream/scan mode
        guard let delay = appState.settings.autoHideDialDelay.seconds,
              viewModel.readingMode == .stream || viewModel.readingMode == .scan else {
            return
        }
        
        // Start new timer
        dialActivityTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            withAnimation {
                isDialHidden = true
            }
        }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button(action: { showLibrary = true }) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
            }

            Spacer()

            ModeSelector(
                selectedMode: $viewModel.readingMode
            )

            Spacer()

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Reading Area
    @ViewBuilder
    private func readingArea(geometry: GeometryProxy, height: CGFloat) -> some View {
        ZStack {
            Group {
                switch viewModel.readingMode {
                case .spritz:
                    SpritzModeView(
                        viewModel: viewModel,
                        fontSize: appState.settings.fontSize
                    )
                case .stream:
                    StreamModeView(
                        viewModel: viewModel,
                        fontSize: appState.settings.fontSize,
                        screenWidth: geometry.size.width,
                        availableHeight: height
                    )
                case .scan:
                    ScanModeView(
                        viewModel: viewModel,
                        fontSize: appState.settings.fontSize,
                        screenWidth: geometry.size.width,
                        availableHeight: height
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .opacity(viewModel.isPaused && showPausedScroll ? 0 : 1)

            if viewModel.isPaused && showPausedScroll {
                PausedScrollView(
                    viewModel: viewModel,
                    fontSize: appState.settings.fontSize,
                    onWordTapped: { index in
                        viewModel.goToWord(at: index)
                    }
                )
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    if viewModel.isPaused {
                        let verticalThreshold: CGFloat = 50
                        if value.translation.height < -verticalThreshold {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showPausedScroll = true
                                viewModel.isDialPushedDown = true
                            }
                        } else if value.translation.height > verticalThreshold {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showPausedScroll = false
                                viewModel.isDialPushedDown = false
                            }
                        }

                        let horizontalThreshold: CGFloat = 30
                        if !showPausedScroll {
                            if value.translation.width < -horizontalThreshold {
                                viewModel.skipForward(words: 1)
                            } else if value.translation.width > horizontalThreshold {
                                viewModel.skipBackward(words: 1)
                            }
                        }
                    }
                }
        )
        .onTapGesture {
            if viewModel.isPaused && showPausedScroll {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showPausedScroll = false
                    viewModel.isDialPushedDown = false
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
                        let bookmark = Bookmark(
                            bookId: book.id,
                            text: viewModel.getBookmarkText(),
                            startWordIndex: viewModel.bookmarkStartIndex,
                            endWordIndex: viewModel.bookmarkEndIndex
                        )
                        appState.addBookmark(bookmark)
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

    // MARK: - Setup
    @MainActor
    private func loadBookContent() async {
        viewModel.isLoading = true
        viewModel.loadingError = nil
        
        do {
            let document = try await parseBook()
            
            viewModel.loadContent(
                words: document.words,
                chapters: document.chapters.isEmpty ? book.chapters : document.chapters,
                startPosition: book.lastReadPosition
            )
            
            // Update book metadata if parsed
            if !document.title.isEmpty && document.title != "Unknown Title" {
                var updatedBook = book
                updatedBook.title = document.title
                updatedBook.author = document.author
                updatedBook.totalWords = document.words.count
                
                // Save cover image to file system
                if let coverData = document.coverImage {
                    try? ImageStorageManager.shared.saveCoverImage(coverData, for: book.id)
                }
                
                appState.updateBook(updatedBook)
            }
            
            // Save any images found in the book
            for parsedImage in document.images {
                let savedImage = SavedImage(
                    bookId: book.id,
                    imageData: parsedImage.data,
                    pageIndex: parsedImage.pageIndex,
                    wordIndex: parsedImage.wordIndex
                )
                appState.addSavedImage(savedImage)
            }
            
            viewModel.wordsPerMinute = appState.settings.defaultWPM
            viewModel.setSoftStartPercentage(appState.settings.softStartPercentage)
            viewModel.readingMode = appState.settings.defaultReadingMode
            
            // Initialize stream mode if that's the default
            if viewModel.readingMode == .stream {
                viewModel.initializeStreamMode()
            }
            
        } catch {
            viewModel.loadingError = error
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
        
        // Check for empty document after successful parse
        if viewModel.words.isEmpty && viewModel.loadingError == nil {
            errorMessage = "This book appears to be empty or could not be read."
            showErrorAlert = true
        }
        
        viewModel.isLoading = false
    }
    
    private func parseBook() async throws -> ParsedDocument {
        // Verify file exists using the valid URL logic (handles container changes)
        let url = book.validURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BookContentManager.ContentError.fileNotFound
        }
        
        switch book.fileType {
        case .epub:
            return try await parser.parseEPub(at: url.path)
        case .pdf:
            return try await parser.parsePDF(at: url.path)
        case .txt:
            return try await parser.parseText(at: url.path)
        }
    }

    private func saveProgress() {
        var updatedBook = book
        updatedBook.lastReadPosition = viewModel.getCurrentPosition()
        updatedBook.lastOpened = Date()
        appState.updateBook(updatedBook)
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

#Preview {
    ReadingView(book: Book(
        title: "Sample Book",
        author: "Test Author",
        filePath: "",
        fileType: .epub
    ))
    .environmentObject(AppState())
}
