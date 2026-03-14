import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var showAccount: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var showURLInput: Bool = false
    @State private var articleURL: String = ""
    @State private var isImporting: Bool = false
    @State private var importError: String? = nil
    @State private var currentContinuePage: Int? = 0
    @State private var previewContext: BookPreviewContext? = nil
    @State private var showCurationSheet: Bool = false
    @State private var editingList: ReadingList? = nil
    @State private var showAddSheet: Bool = false
    @State private var selectedStatus: LibraryItem.InferredReadingStatus? = nil
    @State private var showFilterSearch: Bool = false
    @State private var filterKeyword: String = ""
    @State private var filterField: FilterField = .title
    @State private var selectedReadingList: ReadingList?
    @Namespace private var libraryGlassNamespace

    private let ingestionService = DocumentIngestionService()

    // MARK: - Filter

    enum FilterField: String, CaseIterable {
        case title = "Title"
        case author = "Author"
        case genre = "Genre"
    }

    private func matchesFilter(_ item: LibraryItem) -> Bool {
        // Status filter
        if let selectedStatus, item.inferredStatus != selectedStatus {
            return false
        }
        // Keyword filter
        guard !filterKeyword.isEmpty else { return true }
        let query = filterKeyword.lowercased()
        switch filterField {
        case .title: return item.title.lowercased().contains(query)
        case .author: return (item.author ?? "").lowercased().contains(query)
        case .genre: return true
        }
    }

    // MARK: - Filtered Data

    private var continueItems: [LibraryItem] {
        appState.library
            .filter { $0.inferredStatus == .reading }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

    private var filteredAllItems: [LibraryItem] {
        appState.library
            .filter { matchesFilter($0) }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    private func filteredItemsForList(_ list: ReadingList) -> [LibraryItem] {
        appState.library
            .filter { list.itemIds.contains($0.id) && matchesFilter($0) }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if appState.library.isEmpty {
                emptyLibraryView
            } else {
                libraryContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await appState.refreshLibraryMetadataFromStoreIfNeeded()
        }
        .sheet(isPresented: $showAccount) {
            AccountView()
        }
        .sheet(isPresented: $showAddSheet) {
            AddContentSheet { action in
                // Delay slightly so the sheet dismissal completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    switch action {
                    case .importFile:
                        showFilePicker = true
                    case .addURL:
                        showURLInput = true
                    case .newCollection:
                        showCurationSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showCurationSheet, onDismiss: { editingList = nil }) {
            CreateCurationSheet(editingList: editingList)
                .environmentObject(appState)
        }
        .sheet(item: $previewContext) { context in
            BookPreviewSheet(
                items: context.items,
                initialIndex: context.initialIndex
            )
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(0)
            .presentationBackground(.clear)
            .environmentObject(appState)
            .environmentObject(readerCoordinator)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.epub, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("Add Article", isPresented: $showURLInput) {
            TextField("https://example.com/article", text: $articleURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { articleURL = "" }
            Button("Add") { importArticle() }
        } message: {
            Text("Enter the URL of the article you want to save for offline reading.")
        }
        .alert("Import Error", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Importing...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button { showAccount = true } label: {
                accountAvatar
            }
            .buttonStyle(.plain)

            Text("Library")
                .font(.hedvigLettersSerif(24))
            Spacer()

            Button { showAddSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var userInitials: String {
        guard let name = authViewModel.userProfile?.displayName else { return "?" }
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
    }

    private var userName: String {
        authViewModel.userProfile?.displayName ?? "Guest"
    }

    private var accountAvatar: some View {
        Circle()
            .fill(Color.darkGold)
            .frame(width: 36, height: 36)
            .overlay {
                Text(userInitials)
                    .font(.hedvigLettersSerif(13))
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle().stroke(Color.goldAccent, lineWidth: 1.5)
            }
            .nativeGlassButton(shape: .circle)
            .conditionalGlassEffectID("accountAvatar", in: libraryGlassNamespace)
    }

    // MARK: - Empty State

    private var emptyLibraryView: some View {
        VStack(spacing: 32) {
            headerBar

            Spacer()

            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.4))

            VStack(spacing: 12) {
                Text("Your Library is Empty")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Import books, PDFs, or save articles\nto start reading")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button(action: { showFilePicker = true }) {
                    Label("Import Book or PDF", systemImage: "doc.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.primary)
                        .foregroundColor(Color(UIColor.systemBackground))
                        .cornerRadius(12)
                }

                Button(action: { showURLInput = true }) {
                    Label("Add Article from URL", systemImage: "link.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Library Content

    @State private var stickyHeaderHeight: CGFloat = 0

    private var topSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 0
    }

    private var stickyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            filterPillsRow

            if showFilterSearch {
                filterSearchBar
            }
        }
        .padding(.bottom, 12)
        .background(
            GeometryReader { geo in
                Color(.systemBackground)
                    .ignoresSafeArea(edges: .top)
                    .preference(key: StickyHeaderHeightKey.self, value: geo.size.height)
            }
        )
    }

    private var libraryContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // Continue pager
                if !continueItems.isEmpty {
                    continuePagerSection
                }

                // Curation-based sections
                let allFiltered = filteredAllItems
                if !allFiltered.isEmpty {
                    coverShelfSection(title: "All", items: allFiltered)
                }

                ForEach(appState.readingLists) { list in
                    let listFiltered = filteredItemsForList(list)
                    if !listFiltered.isEmpty {
                        coverShelfSection(title: list.name, items: listFiltered, list: list)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.top, 12)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            stickyHeader
        }
        .onPreferenceChange(StickyHeaderHeightKey.self) { height in
            stickyHeaderHeight = height
        }
        .navigationDestination(item: $selectedReadingList) { list in
            CurationDetailView(readingList: list)
                .environmentObject(appState)
                .environmentObject(readerCoordinator)
        }
    }

    // MARK: - Filter Pills

    private let pillColor = Color.primary

    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Filter icon button
                Button {
                    withAnimation {
                        showFilterSearch.toggle()
                        if !showFilterSearch {
                            filterKeyword = ""
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 30, height: 30)
                        .background(showFilterSearch ? pillColor.opacity(0.18) : pillColor.opacity(0.08))
                        .clipShape(Capsule())
                }

                // "All" pill
                statusPill(label: "All", status: nil)

                // Status pills
                statusPill(label: "In Progress", status: .reading)
                statusPill(label: "Completed", status: .completed)
                statusPill(label: "Never Read", status: .wantToRead)
            }
            .padding(.horizontal, 20)
        }
    }

    private func statusPill(label: String, status: LibraryItem.InferredReadingStatus?) -> some View {
        let isSelected = selectedStatus == status
        return Button {
            if isSelected {
                selectedStatus = nil
            } else {
                selectedStatus = status
            }
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(label)
            }
            .font(.rethinkSans(13))
            .foregroundStyle(Color(UIColor.label))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(pillColor.opacity(isSelected ? 0.18 : 0.08))
            .clipShape(Capsule())
        }
    }

    // MARK: - Filter Search Bar

    private var filterSearchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $filterKeyword)
                    .font(.rethinkSans(14))
                    .textFieldStyle(.plain)
                if !filterKeyword.isEmpty {
                    Button { filterKeyword = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Picker("Field", selection: $filterField) {
                ForEach(FilterField.allCases, id: \.self) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Continue Pager

    private var continuePagerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue")
                .font(.hedvigLettersSerif(20))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(continueItems.enumerated()), id: \.element.id) { index, item in
                        ContinueCard(item: item, appState: appState)
                            .padding(.horizontal, 20)
                            .containerRelativeFrame(.horizontal)
                            .onTapGesture {
                                readerCoordinator.openItem(item, appState: appState)
                            }
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentContinuePage)

            if continueItems.count > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<continueItems.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentContinuePage ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Cover Shelf Section

    private func coverShelfSection(title: String, items: [LibraryItem], list: ReadingList? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let list {
                Button {
                    selectedReadingList = list
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.hedvigLettersSerif(20))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .contextMenu {
                    Button {
                        editingList = list
                        showCurationSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        appState.deleteReadingList(list.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.hedvigLettersSerif(20))
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        libraryCoverCard(item: item)
                            .onTapGesture {
                                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                                    previewContext = BookPreviewContext(items: items, initialIndex: idx)
                                }
                            }
                            .contextMenu {
                                ForEach(appState.readingLists) { list in
                                    Button {
                                        appState.addItemToList(item.id, listId: list.id)
                                    } label: {
                                        Label(list.name, systemImage: list.itemIds.contains(item.id) ? "checkmark" : "list.bullet")
                                    }
                                }
                                Button {
                                    showCurationSheet = true
                                } label: {
                                    Label("New List...", systemImage: "plus")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    appState.deleteItem(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            }
        }
    }

    // MARK: - Cover Card

    private func libraryCoverCard(item: LibraryItem) -> some View {
        BookCoverView(
            coverImageData: appState.getCoverImage(for: item.documentId),
            coverURL: item.curatedCoverURL,
            title: item.title,
            iconName: item.coverIconName,
            ribbonState: item.ribbonState,
            flexibleAspectRatio: true
        )
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let fileType: DocumentSource.LocalFileType
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "epub":
                fileType = .epub
            case "pdf":
                fileType = .pdf
            default:
                importError = "Unsupported file type. Please import an EPUB or PDF."
                return
            }

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)

                isImporting = true
                Task {
                    defer {
                        Task { @MainActor in isImporting = false }
                    }

                    let documentId = UUID()
                    do {
                        let source = DocumentSource.localFile(.init(url: destinationURL, fileType: fileType))
                        let packages = try await ingestionService.ingestCanonicalPackages(
                            source: source,
                            documentId: documentId
                        )

                        let item = LibraryItem(
                            documentId: documentId,
                            source: .localFile(.init(fileURL: destinationURL, fileType: fileType)),
                            title: packages.manifest.title,
                            author: packages.manifest.authors.first
                        )

                        await MainActor.run {
                            appState.addItem(item)
                        }
                    } catch {
                        await MainActor.run {
                            importError = "Failed to import file: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                importError = "Failed to copy file: \(error.localizedDescription)"
            }

        case .failure(let error):
            importError = "File picker error: \(error.localizedDescription)"
        }
    }

    // MARK: - Article Import

    private func importArticle() {
        guard let url = URL(string: articleURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            importError = "Please enter a valid URL starting with http:// or https://"
            articleURL = ""
            return
        }

        isImporting = true
        articleURL = ""

        Task {
            defer {
                Task { @MainActor in isImporting = false }
            }

            let documentId = UUID()
            do {
                let source = DocumentSource.web(.init(url: url))
                let packages = try await ingestionService.ingestCanonicalPackages(
                    source: source,
                    documentId: documentId
                )

                let item = LibraryItem(
                    documentId: documentId,
                    source: .web(.init(url: url, lastRefreshedAt: Date())),
                    title: packages.manifest.title,
                    author: packages.manifest.authors.first
                )

                await MainActor.run {
                    appState.addItem(item)
                }
            } catch {
                await MainActor.run {
                    importError = "Failed to import article: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Conditional Modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Sticky Header Height Preference Key

private struct StickyHeaderHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - UTType Extension
extension UTType {
    static let epub = UTType(filenameExtension: "epub") ?? .data
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(AppState())
            .environmentObject(ReaderCoordinator())
    }
}
