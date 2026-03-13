import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showStatsSheet = false
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var statsVM: ReadingStatsViewModel?
    @State private var timelineVM: HomeTimelineViewModel?
    @State private var selectedCurationItem: CurationItem?
    @State private var curationPreviewContext: CurationPreviewContext?
    @State private var showAccount: Bool = false
    @Namespace private var homeGlassNamespace

    // Paging state
    @State private var currentDayPage: UUID?
    @State private var currentSectionTitle: String = "Today's Curation"
    @State private var hasScrolledToToday = false
    private let statsPageId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // Cover carousel state
    @State private var carouselCenters: [UUID: Int] = [:]

    var scrollToTodayTrigger: Bool = false
    var onNavigateToCurator: (() -> Void)?

    // MARK: - Body

    var body: some View {
        ZStack {
            if appState.library.isEmpty && (timelineVM?.dayCurations.isEmpty ?? true) {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if let vm = timelineVM {
                            ForEach(vm.dayCurations) { day in
                                dayCurationSection(day)
                                    .containerRelativeFrame(.vertical)
                                    .id(day.id)
                            }
                        }

                        // Stats page — scrolling down past today reveals this
                        if let statsVM {
                            inlineStatsPage(statsVM: statsVM)
                                .containerRelativeFrame(.vertical)
                                .id(statsPageId)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentDayPage)
            }
        }
        .overlay(alignment: .top) {
            if !(appState.library.isEmpty && (timelineVM?.dayCurations.isEmpty ?? true)) {
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
                .padding(.top, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: currentDayPage) {
            updateSectionTitle()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await statsVM?.load() }
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
            await statsVM?.load()
            await timelineVM?.load()

            // Scroll to today on first load
            if !hasScrolledToToday, let todayId = timelineVM?.todayCurationId {
                hasScrolledToToday = true
                try? await Task.sleep(for: .milliseconds(300))
                currentDayPage = todayId
            }
        }
        .onAppear {
            Task { await statsVM?.load() }
        }
        .onChange(of: scrollToTodayTrigger) {
            if let todayId = timelineVM?.todayCurationId {
                withAnimation {
                    currentDayPage = todayId
                }
            }
        }
        .sheet(isPresented: $showStatsSheet) {
            if let statsVM {
                ReadingStatsSheet(statsVM: statsVM)
            }
        }
        .sheet(isPresented: $showAccount) {
            AccountView()
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .sheet(item: $selectedCurationItem) { item in
            CurationItemDetailSheet(
                item: item,
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $curationPreviewContext) { context in
            CurationPreviewSheet(
                items: context.items,
                initialIndex: context.initialIndex,
                onSelectItem: { item in
                    curationPreviewContext = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedCurationItem = item
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

        VStack(spacing: 0) {
            if !items.isEmpty {
                // Summary text — scrollable within the page
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if let summary = day.curation.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.rethinkSans(16))
                                .foregroundStyle(.primary.opacity(0.85))
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 72)
                }

                Spacer(minLength: 20)

                // 3-item focused cover carousel
                curationCoverCarousel(for: items, dayId: day.id)

                Spacer().frame(height: 100)
            } else {
                // Empty curation placeholder
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
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .onAppear {
            // Load earlier pages when first page appears
            if let vm = timelineVM, day.id == vm.dayCurations.first?.id {
                Task { await vm.loadEarlier() }
            }
        }
    }

    // MARK: - 3-Item Focused Cover Carousel

    @ViewBuilder
    private func curationCoverCarousel(for items: [CurationItem], dayId: UUID) -> some View {
        let sorted = items.sorted { a, b in
            let aHasCover = a.content?.coverUrl != nil
            let bHasCover = b.content?.coverUrl != nil
            if aHasCover != bHasCover { return aHasCover }
            return a.position < b.position
        }

        if sorted.isEmpty { EmptyView() }
        else {
            let centerIdx = (carouselCenters[dayId] ?? 0) % sorted.count
            let visibleSlots: [(pos: Int, item: CurationItem, idx: Int)] = {
                var slots: [(Int, CurationItem, Int)] = []
                slots.append((0, sorted[centerIdx], centerIdx))
                if sorted.count > 1 {
                    let leftIdx = (centerIdx - 1 + sorted.count) % sorted.count
                    slots.append((-1, sorted[leftIdx], leftIdx))
                }
                if sorted.count > 2 {
                    let rightIdx = (centerIdx + 1) % sorted.count
                    slots.append((1, sorted[rightIdx], rightIdx))
                }
                return slots
            }()

            VStack(spacing: 0) {
                ZStack {
                    ForEach(visibleSlots, id: \.item.id) { pos, item, idx in
                        coverThumbnail(item: item, width: 51, height: 75)
                            .scaleEffect(pos == 0 ? 1.0 : 0.75)
                            .opacity(pos == 0 ? 1.0 : 0.5)
                            .offset(x: CGFloat(pos) * 70)
                            .zIndex(pos == 0 ? 1 : 0)
                            .onTapGesture {
                                if pos == 0 {
                                    curationPreviewContext = CurationPreviewContext(
                                        items: sorted,
                                        initialIndex: centerIdx
                                    )
                                } else {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        carouselCenters[dayId] = idx
                                    }
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.3), value: carouselCenters[dayId])
                .gesture(
                    DragGesture(minimumDistance: 30, coordinateSpace: .local)
                        .onEnded { value in
                            guard sorted.count > 1 else { return }
                            let current = carouselCenters[dayId] ?? 0
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if value.translation.width < 0 {
                                    carouselCenters[dayId] = (current + 1) % sorted.count
                                } else {
                                    carouselCenters[dayId] = (current - 1 + sorted.count) % sorted.count
                                }
                            }
                        }
                )
                .onAppear {
                    if carouselCenters[dayId] == nil {
                        carouselCenters[dayId] = 0
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func coverThumbnail(item: CurationItem, width: CGFloat, height: CGFloat) -> some View {
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
            .id(urlString)
        } else {
            fallbackCover(title: item.displayTitle, width: width, height: height)
        }
    }

    private func fallbackCover(title: String, width: CGFloat, height: CGFloat) -> some View {
        let colors = Color.fallbackCoverPalette.map { Color(hex: $0) }
        let index = abs(title.hashValue) % colors.count
        return RoundedRectangle(cornerRadius: 4)
            .fill(colors[index])
            .frame(width: width, height: height)
    }

    // MARK: - Section Title Tracking

    private func updateSectionTitle() {
        guard let vm = timelineVM, let pageId = currentDayPage else {
            currentSectionTitle = "Today's Curation"
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

    // MARK: - Inline Stats Page

    private func inlineStatsPage(statsVM: ReadingStatsViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Today section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today")
                        .font(.hedvigLettersSerif(20))

                    HStack(spacing: 12) {
                        SummaryStatCard(
                            icon: "clock.fill",
                            iconColor: .blue,
                            value: formatStatsTime(statsVM.todayReadingSeconds),
                            label: "Reading Time"
                        )
                        SummaryStatCard(
                            icon: "text.word.spacing",
                            iconColor: .purple,
                            value: formatStatsWords(statsVM.todayWordsRead),
                            label: "Words Read"
                        )
                    }
                }

                Divider()

                // Lifetime stats
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    SummaryStatCard(
                        icon: "flame.fill",
                        iconColor: .orange,
                        value: "\(statsVM.statsCache?.currentStreak ?? 0)",
                        label: "Current Streak"
                    )
                    SummaryStatCard(
                        icon: "clock.fill",
                        iconColor: .blue,
                        value: formatStatsTime(statsVM.statsCache?.totalReadingSeconds ?? 0),
                        label: "Total Time"
                    )
                    SummaryStatCard(
                        icon: "speedometer",
                        iconColor: .green,
                        value: "\(statsVM.statsCache?.lifetimeAvgWPM ?? 0)",
                        label: "Avg WPM"
                    )
                    SummaryStatCard(
                        icon: "text.word.spacing",
                        iconColor: .purple,
                        value: formatStatsWords(statsVM.statsCache?.totalWordsRead ?? 0),
                        label: "Words Read"
                    )
                    SummaryStatCard(
                        icon: "books.vertical.fill",
                        iconColor: .indigo,
                        value: "\(statsVM.statsCache?.booksFinished ?? 0)",
                        label: "Books"
                    )
                    SummaryStatCard(
                        icon: "calendar",
                        iconColor: .teal,
                        value: "\(statsVM.statsCache?.daysRead ?? 0)",
                        label: "Days Read"
                    )
                }

                // "See more" button to open full stats sheet
                Button {
                    showStatsSheet = true
                } label: {
                    HStack {
                        Text("View Full Stats")
                            .font(.rethinkSans(15, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.goldAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 40)
        }
        .task { await statsVM.load() }
    }

    private func formatStatsTime(_ seconds: Int) -> String {
        if seconds == 0 { return "0m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }

    private func formatStatsWords(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 100_000 { return String(format: "%.1fk", Double(count) / 1000.0) }
        if count < 1_000_000 { return "\(count / 1000)k" }
        return String(format: "%.1fM", Double(count) / 1_000_000.0)
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
