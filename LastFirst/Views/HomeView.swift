import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var statsVM: ReadingStatsViewModel?
    @State private var timelineVM: HomeTimelineViewModel?
    @State private var curationPreviewContext: CurationPreviewContext?
    @State private var showAccount: Bool = false
    @Namespace private var homeGlassNamespace

    // Paging state
    @State private var currentDayPage: UUID?
    @State private var currentSectionTitle: String = "Today's Curation"
    @State private var hasScrolledToToday = false
    @State private var carouselCenters: [UUID: Int] = [:]
    private let statsPageId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var scrollToTodayTrigger: Bool = false
    var onNavigateToCurator: (() -> Void)?

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if isInitialTimelineLoading {
                homeLoadingState
            } else if shouldShowEmptyState {
                emptyState
            } else {
                GeometryReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if let vm = timelineVM {
                                if vm.shouldShowGeneratingTodayPage, let pendingTodayId = vm.pendingTodayCurationId {
                                    generatingTodayPage
                                        .frame(maxWidth: .infinity)
                                        .frame(height: proxy.size.height)
                                        .background(Color(.systemBackground))
                                        .contentShape(Rectangle())
                                        .clipped()
                                        .scrollTransition(.animated(.easeInOut(duration: 0.3))) { content, phase in
                                            content.opacity(phase.isIdentity ? 1.0 : 0.85)
                                                   .scaleEffect(phase.isIdentity ? 1.0 : 0.95)
                                        }
                                        .id(pendingTodayId)
                                }

                                ForEach(vm.dayCurations) { day in
                                    dayCurationSection(day)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: proxy.size.height)
                                        .background(Color(.systemBackground))
                                        .contentShape(Rectangle())
                                        .clipped()
                                        .scrollTransition(.animated(.easeInOut(duration: 0.3))) { content, phase in
                                            content.opacity(phase.isIdentity ? 1.0 : 0.85)
                                                   .scaleEffect(phase.isIdentity ? 1.0 : 0.95)
                                        }
                                        .id(day.id)
                                }
                            }

                            // Stats page — scrolling down past today reveals this
                            if shouldShowStatsPage, let statsVM {
                                ReadingStatsPageView(statsVM: statsVM)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: proxy.size.height)
                                    .background(Color(.systemBackground))
                                    .contentShape(Rectangle())
                                    .clipped()
                                    .scrollTransition(.animated(.easeInOut(duration: 0.3))) { content, phase in
                                        content.opacity(phase.isIdentity ? 1.0 : 0.85)
                                               .scaleEffect(phase.isIdentity ? 1.0 : 0.95)
                                    }
                                    .id(statsPageId)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentDayPage)
                    .defaultScrollAnchor(.bottom)
                    .background(Color(.systemBackground))
                    .clipped()
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isInitialTimelineLoading,
               !shouldShowEmptyState {
                HStack {
                    Button { showAccount = true } label: {
                        accountAvatar
                    }
                    .buttonStyle(.plain)

                    Text(currentSectionTitle)
                        .font(.hedvigLettersSerif(24))
                    Spacer()

                    Button { showDatePicker = true } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemBackground).ignoresSafeArea(edges: .top))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: currentDayPage) { oldValue, newValue in
            updateSectionTitle()
            if hasScrolledToToday && oldValue != nil {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            Task { await loadEarlierIfNeeded(for: newValue) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await timelineVM?.load()
                    await statsVM?.load()
                    await scrollToToday(force: true)
                }
            }
        }
        .onChange(of: authVM.currentUser?.id) { _, newUserId in
            Task {
                await handleAuthChange(newUserId)
            }
        }
        .task {
            if statsVM == nil {
                let userId = authVM.currentUser?.id.uuidString ?? "local"
                statsVM = ReadingStatsViewModel(modelContext: modelContext, appState: appState, userId: userId)
            }
            if timelineVM == nil, let userId = authVM.currentUser?.id {
                timelineVM = HomeTimelineViewModel(userId: userId)
            }
            await timelineVM?.load()
            await statsVM?.load()
            await scrollToToday(force: true)
        }
        .onAppear {
            Task {
                if currentDayPage == nil {
                    await scrollToToday(force: true)
                }
            }
        }
        .onChange(of: timelinePageIDs) { _, newValue in
            guard !newValue.isEmpty else { return }
            let currentPageStillExists = currentDayPage.map(newValue.contains) ?? false
            let shouldReanchor = currentDayPage == nil
                || !hasScrolledToToday
                || !currentPageStillExists
                || currentDayPage != timelineVM?.todayCurationId
            guard shouldReanchor else { return }
            Task {
                await scrollToToday(force: true)
            }
        }
        .onChange(of: scrollToTodayTrigger) { _, _ in
            Task {
                await scrollToToday(animated: true, force: true)
            }
        }
        .sheet(isPresented: $showAccount) {
            AccountView()
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .sheet(item: $curationPreviewContext) { context in
            CurationPreviewSheet(
                items: context.items,
                initialIndex: context.initialIndex,
                userId: authVM.currentUser?.id,
                onSave: { curationItem in
                    appState.addCuratedItem(curationItem)
                    Task {
                        try? await SupabaseManager.shared.markCurationItemSaved(itemId: curationItem.id)
                        if let contentId = curationItem.contentId, let userId = authVM.currentUser?.id {
                            try? await SupabaseManager.shared.postInteraction(
                                userId: userId,
                                contentId: contentId,
                                kind: "bookmark"
                            )
                        }
                    }
                }
            )
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(0)
            .presentationBackground(.clear)
        }
    }

    // MARK: - Day Curation Section

    @ViewBuilder
    private func dayCurationSection(_ day: DayCuration) -> some View {
        let items = day.items

        if !items.isEmpty {
            GeometryReader { geo in
                let pages = paginateSummary(
                    day.curation.summary ?? "",
                    availableSize: geo.size
                )
                let sortedItems = items.sorted { a, b in
                    let aHasCover = a.content?.coverUrl != nil
                    let bHasCover = b.content?.coverUrl != nil
                    if aHasCover != bHasCover { return aHasCover }
                    return a.position < b.position
                }

                if pages.count <= 1 {
                    // Single page — no horizontal scroll needed
                    summaryPage(
                        text: pages.first ?? "",
                        pageIndex: 0,
                        totalPages: 1,
                        items: sortedItems,
                        dayId: day.id,
                        isToday: day.isToday,
                        availableHeight: geo.size.height
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { index, text in
                                summaryPage(
                                    text: text,
                                    pageIndex: index,
                                    totalPages: pages.count,
                                    items: sortedItems,
                                    dayId: day.id,
                                    isToday: day.isToday,
                                    availableHeight: geo.size.height
                                )
                                .containerRelativeFrame(.horizontal)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
            .onAppear {
                if let vm = timelineVM,
                   hasScrolledToToday,
                   currentDayPage == day.id,
                   day.id == vm.earliestLoadedDayId {
                    Task { await vm.loadEarlier() }
                }
            }
        } else {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("Your daily curation is being prepared...")
                        .font(.rethinkSans(14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
            .onAppear {
                if let vm = timelineVM,
                   hasScrolledToToday,
                   currentDayPage == day.id,
                   day.id == vm.earliestLoadedDayId {
                    Task { await vm.loadEarlier() }
                }
            }
        }
    }

    // MARK: - Summary Page

    private func summaryPage(
        text: String,
        pageIndex: Int,
        totalPages: Int,
        items: [CurationItem],
        dayId: UUID,
        isToday: Bool,
        availableHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            // Summary text — fills available space
            if !text.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(.rethinkSans(16))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            Spacer(minLength: 8)

            // Page indicator dots (only if multiple pages)
            if totalPages > 1 {
                pageIndicatorDots(current: pageIndex, total: totalPages)
                    .padding(.bottom, 8)
            }

            // Mini book preview strip
            miniBookPreview(items: items, dayId: dayId)
                .padding(.bottom, 8)

            Spacer().frame(height: availableHeight * 0.10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Page Indicator Dots

    private func pageIndicatorDots(current: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Mini Book Preview Strip

    private func miniBookPreview(items: [CurationItem], dayId: UUID) -> some View {
        let centerIndex = carouselCenters[dayId] ?? 0
        let clamped = min(max(centerIndex, 0), items.count - 1)
        let coverWidth: CGFloat = 80
        let coverHeight: CGFloat = 118
        let coverOffset: CGFloat = 106

        return ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let pos = index - clamped
                if abs(pos) <= 1 {
                    coverThumbnail(item: item, width: coverWidth, height: coverHeight)
                        .scaleEffect(pos == 0 ? 1.0 : 0.75)
                        .opacity(pos == 0 ? 1.0 : 0.5)
                        .offset(x: CGFloat(pos) * coverOffset)
                        .zIndex(pos == 0 ? 1 : 0)
                        .onTapGesture {
                            if pos == 0 {
                                curationPreviewContext = CurationPreviewContext(
                                    items: items,
                                    initialIndex: clamped
                                )
                            } else {
                                shiftCarouselCenter(for: dayId, itemCount: items.count, to: index)
                            }
                        }
                }
            }
        }
        .frame(height: coverHeight)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontalTranslation = value.translation.width
                    let verticalTranslation = value.translation.height
                    guard abs(horizontalTranslation) > abs(verticalTranslation),
                          abs(horizontalTranslation) > 40 else { return }
                    let nextIndex = clamped + (horizontalTranslation < 0 ? 1 : -1)
                    shiftCarouselCenter(for: dayId, itemCount: items.count, to: nextIndex)
                }
        )
        .animation(.easeInOut(duration: 0.3), value: carouselCenters[dayId])
    }

    private func shiftCarouselCenter(for dayId: UUID, itemCount: Int, to proposedIndex: Int) {
        guard itemCount > 0 else { return }
        let currentIndex = min(max(carouselCenters[dayId] ?? 0, 0), itemCount - 1)
        let nextIndex = min(max(proposedIndex, 0), itemCount - 1)
        guard nextIndex != currentIndex else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            carouselCenters[dayId] = nextIndex
        }
    }

    // MARK: - Cover Thumbnail

    private func coverThumbnail(item: CurationItem, width: CGFloat = 80, height: CGFloat = 118) -> some View {
        Group {
            if let urlString = item.content?.coverUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    case .failure:
                        fallbackCover(title: item.displayTitle, width: width, height: height)
                    default:
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: width, height: height)
                    }
                }
            } else {
                fallbackCover(title: item.displayTitle, width: width, height: height)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private func fallbackCover(title: String, width: CGFloat = 80, height: CGFloat = 118) -> some View {
        let colors = Color.fallbackCoverPalette.map { Color(hex: $0) }
        let index = abs(title.hashValue) % colors.count
        return RoundedRectangle(cornerRadius: 4)
            .fill(colors[index])
            .frame(width: width, height: height)
            .overlay {
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            }
    }

    // MARK: - Summary Pagination

    private func paginateSummary(_ text: String, availableSize: CGSize) -> [String] {
        guard !text.isEmpty else { return [""] }

        let font = UIFont(name: "RethinkSans-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let constraintWidth = availableSize.width - 48 // 24pt horizontal padding each side

        let fullSize = (text as NSString).boundingRect(
            with: CGSize(width: constraintWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        let reservedHeight: CGFloat = 208
        let availableTextHeight = availableSize.height - reservedHeight

        guard availableTextHeight > 60 else { return [text] }

        // If text fits in one page, return as-is
        if fullSize.height <= availableTextHeight {
            return [text]
        }

        // Split at sentence boundaries
        let sentences = splitIntoSentences(text)
        var pages: [String] = []
        var currentPage = ""

        for sentence in sentences {
            let candidate = currentPage.isEmpty ? sentence : currentPage + sentence
            let candidateSize = (candidate as NSString).boundingRect(
                with: CGSize(width: constraintWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )

            if candidateSize.height > availableTextHeight && !currentPage.isEmpty {
                pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                currentPage = sentence
            } else {
                currentPage = candidate
            }
        }

        if !currentPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return pages.isEmpty ? [text] : pages
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            current.append(chars[i])
            if chars[i] == "." || chars[i] == "!" || chars[i] == "?" {
                // Check if followed by space/newline or end of string
                let next = i + 1
                if next >= chars.count || chars[next] == " " || chars[next] == "\n" {
                    // Include trailing space/newline
                    if next < chars.count && (chars[next] == " " || chars[next] == "\n") {
                        current.append(chars[next])
                        i += 1
                    }
                    sentences.append(current)
                    current = ""
                }
            }
            i += 1
        }

        if !current.isEmpty {
            sentences.append(current)
        }

        return sentences
    }

    // MARK: - Section Title Tracking

    private func updateSectionTitle() {
        guard let vm = timelineVM, let pageId = currentDayPage else {
            currentSectionTitle = shouldShowStatsPage && !hasHomeTimelineContent ? "Reading Stats" : "Today's Curation"
            return
        }

        if pageId == statsPageId {
            currentSectionTitle = "Reading Stats"
        } else if let day = vm.dayCurations.first(where: { $0.id == pageId }) {
            if day.isToday {
                currentSectionTitle = "Today's Curation"
            } else {
                currentSectionTitle = formatDateHeader(day.date)
            }
        } else {
            currentSectionTitle = "Today's Curation"
        }
    }

    // MARK: - Date Picker Sheet

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Jump to date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(20)
                .navigationTitle("Jump to Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDatePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            showDatePicker = false
                            scrollToDate(selectedDate)
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today's Curation" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: date)
        }
        let day = calendar.component(.day, from: date)
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        let month = f.string(from: date)
        let suffix = ordinalSuffix(for: day)
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return "\(month) \(day)\(suffix)"
        }
        return "\(month) \(day)\(suffix), \(calendar.component(.year, from: date))"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 11, 12, 13: return "th"
        default:
            switch day % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }

    private func scrollToDate(_ date: Date) {
        guard let vm = timelineVM else { return }
        let calendar = Calendar.current
        if let match = vm.dayCurations.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            withAnimation {
                currentDayPage = match.id
            }
        }
    }

    private var shouldShowGeneratingTodayPage: Bool {
        timelineVM?.shouldShowGeneratingTodayPage ?? false
    }

    private var hasHomeTimelineContent: Bool {
        shouldShowGeneratingTodayPage || !(timelineVM?.dayCurations.isEmpty ?? true)
    }

    private var shouldShowEmptyState: Bool {
        appState.library.isEmpty && !hasHomeTimelineContent
    }

    private var timelinePageIDs: [UUID] {
        var ids = timelineVM?.dayCurations.map(\.id) ?? []
        if shouldShowGeneratingTodayPage, let pendingTodayId = timelineVM?.pendingTodayCurationId {
            ids.append(pendingTodayId)
        }
        return ids
    }

    private var isInitialTimelineLoading: Bool {
        guard authVM.currentUser != nil else { return false }
        guard let vm = timelineVM else { return true }
        return !vm.hasResolvedInitialTimeline && vm.dayCurations.isEmpty && !vm.shouldShowGeneratingTodayPage
    }

    private var shouldShowStatsPage: Bool {
        guard statsVM != nil else { return false }
        if authVM.currentUser == nil {
            return !appState.library.isEmpty
        }
        guard let vm = timelineVM else { return false }
        return hasHomeTimelineContent || vm.hasResolvedInitialTimeline
    }

    private func loadEarlierIfNeeded(for pageId: UUID?) async {
        guard let pageId,
              let vm = timelineVM,
              pageId == vm.earliestLoadedDayId else { return }
        await vm.loadEarlier()
    }

    private func handleAuthChange(_ newUserId: UUID?) async {
        statsVM = ReadingStatsViewModel(
            modelContext: modelContext,
            appState: appState,
            userId: newUserId?.uuidString ?? "local"
        )
        await statsVM?.load()
        hasScrolledToToday = false
        currentDayPage = nil

        if let newUserId {
            timelineVM = HomeTimelineViewModel(userId: newUserId)
            await timelineVM?.load()
            await scrollToToday(force: true)
        } else {
            timelineVM = nil
            await anchorToStatsPageIfNeeded(force: true)
        }
    }

    private func scrollToToday(animated: Bool = false, force: Bool = false) async {
        guard let vm = timelineVM else {
            await anchorToStatsPageIfNeeded(animated: animated, force: force)
            return
        }
        guard let todayId = vm.todayCurationId else {
            await anchorToStatsPageIfNeeded(animated: animated, force: force)
            return
        }
        guard vm.dayCurations.contains(where: { $0.id == todayId }) || vm.pendingTodayCurationId == todayId else {
            await anchorToStatsPageIfNeeded(animated: animated, force: force)
            return
        }
        guard force || !hasScrolledToToday || currentDayPage != todayId else { return }

        await MainActor.run {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentDayPage = todayId
                }
            } else {
                currentDayPage = todayId
            }
            hasScrolledToToday = true
            updateSectionTitle()
        }
    }

    private func anchorToStatsPageIfNeeded(animated: Bool = false, force: Bool = false) async {
        guard shouldShowStatsPage, !hasHomeTimelineContent else { return }
        guard force || currentDayPage != statsPageId else { return }

        await MainActor.run {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentDayPage = statsPageId
                }
            } else {
                currentDayPage = statsPageId
            }
            hasScrolledToToday = false
            updateSectionTitle()
        }
    }

    // MARK: - Account Avatar

    private var userInitials: String {
        guard let name = authVM.userProfile?.displayName else { return "?" }
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
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
            .conditionalGlassEffectID("accountAvatar", in: homeGlassNamespace)
    }

    private var homeLoadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.1)
            Text("Loading today’s curation…")
                .font(.rethinkSans(15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generatingTodayPage: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("Your daily curation is being prepared...")
                .font(.rethinkSans(14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
