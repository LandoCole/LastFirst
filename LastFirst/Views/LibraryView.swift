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
    @State private var sortOption: SortOption = .dateAdded
    @State private var currentContinuePage: Int? = 0
    @State private var previewContext: BookPreviewContext? = nil
    @Namespace private var libraryGlassNamespace

    private let ingestionService = DocumentIngestionService()

    // MARK: - Sort

    enum SortOption: String, CaseIterable {
        case dateAdded = "Date Added"
        case title = "Title"
        case author = "Author"
        case lastOpened = "Last Opened"
    }

    // MARK: - Filtered Data

    private var continueItems: [LibraryItem] {
        appState.library
            .filter { $0.inferredStatus == .reading }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

    private var allItems: [LibraryItem] {
        sortedItems(appState.library)
    }

    private var inProgressItems: [LibraryItem] {
        appState.library
            .filter { $0.inferredStatus == .reading }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

    private var completedItems: [LibraryItem] {
        appState.library
            .filter { $0.inferredStatus == .completed }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    private var wantToReadItems: [LibraryItem] {
        appState.library
            .filter { $0.inferredStatus == .wantToRead }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    private func sortedItems(_ items: [LibraryItem]) -> [LibraryItem] {
        switch sortOption {
        case .dateAdded:
            return items.sorted { $0.dateAdded > $1.dateAdded }
        case .title:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author:
            return items.sorted { ($0.author ?? "") < ($1.author ?? "") }
        case .lastOpened:
            return items.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
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
            Text("Library")
                .font(.hedvigLettersSerif(24))
            Spacer()

            Menu {
                Button("Import Book or PDF") { showFilePicker = true }
                Button("Add Article from URL") { showURLInput = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .tint(.primary)
            .glassStyle(shape: .circle)
            .conditionalGlassEffectID("importMenu", in: libraryGlassNamespace)

            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .tint(.primary)
            .glassStyle(shape: .circle)
            .conditionalGlassEffectID("sortMenu", in: libraryGlassNamespace)

            Button { showAccount = true } label: {
                accountPill
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

    private var accountPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "B8860B"))
                .frame(width: 34, height: 34)
                .overlay {
                    Text(userInitials)
                        .font(.hedvigLettersSerif(11))
                        .foregroundStyle(.white)
                }

            Text(userName)
                .font(.rethinkSans(11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.trailing, 12)
        .frame(height: 44)
        .glassStyle(shape: .pill)
        .conditionalGlassEffectID("accountPill", in: libraryGlassNamespace)
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

    private var libraryContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                headerBar

                // Continue pager
                if !continueItems.isEmpty {
                    continuePagerSection
                }

                // Shelf sections
                coverShelfSection(title: "All", items: allItems)

                if !inProgressItems.isEmpty {
                    coverShelfSection(title: "In Progress", items: inProgressItems)
                }

                if !completedItems.isEmpty {
                    coverShelfSection(title: "Completed", items: completedItems)
                }

                if !wantToReadItems.isEmpty {
                    coverShelfSection(title: "Want to Read", items: wantToReadItems)
                }
            }
            .padding(.vertical, 8)
        }
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

    private func coverShelfSection(title: String, items: [LibraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.hedvigLettersSerif(20))
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

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
            title: item.title,
            iconName: item.coverIconName,
            ribbonState: item.ribbonState
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
