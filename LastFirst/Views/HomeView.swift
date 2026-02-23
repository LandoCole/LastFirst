import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var showPastCurations = false
    @State private var showStatsSheet = false
    @State private var currentContinuePage: Int? = 0
    @State private var previewContext: BookPreviewContext? = nil
    @State private var statsVM: ReadingStatsViewModel?
    @State private var catalogVM = CatalogViewModel()
    @State private var selectedCatalogItem: CatalogItem?
    @Namespace private var homeGlassNamespace

    var onNavigateToCurator: (() -> Void)?

    // MARK: - Filtered Data

    private var continueReadingItems: [LibraryItem] {
        appState.library
            .filter { $0.lastOpenedAt != nil && $0.progress.percentComplete > 0 && $0.progress.percentComplete < 100 }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

    private var quickReads: [LibraryItem] {
        let withCount = appState.library.filter { $0.wordCount != nil }
        if withCount.isEmpty {
            return Array(appState.library
                .filter { $0.progress.percentComplete == 0 }
                .prefix(6))
        }
        let sorted = withCount.sorted { ($0.wordCount ?? 0) < ($1.wordCount ?? 0) }
        return Array(sorted.prefix(sorted.count / 2 + 1))
    }

    private var greatReads: [LibraryItem] {
        let withCount = appState.library.filter { $0.wordCount != nil }
        guard !withCount.isEmpty else { return [] }
        let sorted = withCount.sorted { ($0.wordCount ?? 0) < ($1.wordCount ?? 0) }
        let midpoint = sorted.count / 2 + 1
        guard midpoint < sorted.count else { return [] }
        return Array(sorted.suffix(from: midpoint))
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            if appState.library.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 32) {
                    todaysCurationSection
                    if !continueReadingItems.isEmpty {
                        continueSection
                    }
                    if let statsVM {
                        ReadingStatsSection(statsVM: statsVM, showStatsSheet: $showStatsSheet)
                    }
                    if !catalogVM.items.isEmpty {
                        discoverSection
                    }
                    if !quickReads.isEmpty {
                        bookShelfSection(title: "Quick Reads", items: quickReads)
                    }
                    if !greatReads.isEmpty {
                        bookShelfSection(title: "Great Reads", items: greatReads)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
        .task {
            if statsVM == nil {
                let userId = authVM.currentUser?.id.uuidString ?? "local"
                statsVM = ReadingStatsViewModel(modelContext: modelContext, appState: appState, userId: userId)
            }
            await statsVM?.load()
            await catalogVM.load()
        }
        .onAppear {
            Task { await statsVM?.load() }
        }
        .sheet(isPresented: $showStatsSheet) {
            if let statsVM {
                ReadingStatsSheet(statsVM: statsVM)
            }
        }
        .sheet(item: $selectedCatalogItem) { item in
            CatalogPreviewSheet(item: item)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPastCurations) {
            NavigationStack {
                Text("Past Curations")
                    .font(.hedvigLettersSerif(24))
                    .navigationTitle("Past Curations")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPastCurations = false }
                        }
                    }
            }
        }
    }

    // MARK: - Today's Curation

    private var todaysCurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with glass buttons
            HStack {
                Text("Today's Curation")
                    .font(.hedvigLettersSerif(24))
                Spacer()

                Button { showPastCurations = true } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .nativeGlassButton(shape: .circle)
                .conditionalGlassEffectID("calendarBtn", in: homeGlassNamespace)
            }
            .padding(.horizontal, 20)

            // Dot matrix placeholder
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "EBEAE4"))
                .frame(height: 310)
                .padding(.horizontal, 20)

        }
    }

    // MARK: - Continue

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue")
                .font(.hedvigLettersSerif(20))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(continueReadingItems.enumerated()), id: \.element.id) { index, item in
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

            if continueReadingItems.count > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<continueReadingItems.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentContinuePage ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Book Shelf (Quick Reads / Great Reads)

    private func bookShelfSection(title: String, items: [LibraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
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
                        bookCover(item: item)
                            .onTapGesture {
                                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                                    previewContext = BookPreviewContext(items: items, initialIndex: idx)
                                }
                            }
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            }
        }
    }

    private func bookCover(item: LibraryItem) -> some View {
        BookCoverView(
            coverImageData: appState.getCoverImage(for: item.documentId),
            title: item.title,
            iconName: item.coverIconName,
            ribbonState: item.ribbonState
        )
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }

    // MARK: - Discover (Catalog)

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discover")
                    .font(.hedvigLettersSerif(20))
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(catalogVM.items) { item in
                        CatalogCoverView(item: item)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            .onTapGesture {
                                selectedCatalogItem = item
                            }
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 80)
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No books yet")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Import a book from the Library tab to get started")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
