import SwiftUI
import Charts

struct ReadingStatsPageView: View {
    @ObservedObject var statsVM: ReadingStatsViewModel
    @State private var currentPage: Int? = 1

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    sessionsPage
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    todayPage
                        .containerRelativeFrame(.horizontal)
                        .id(1)
                    chartPage
                        .containerRelativeFrame(.horizontal)
                        .id(2)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentPage)

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .clipped()
        .task { await statsVM.load() }
    }

    // MARK: - Sessions Page

    private var sessionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Sessions")
                .font(.hedvigLettersSerif(20))
                .padding(.horizontal, 24)
                .padding(.top, 16)

            if statsVM.recentSessions.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No sessions yet")
                        .font(.rethinkSans(14))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(statsVM.recentSessions, id: \.id) { session in
                            SessionRow(
                                session: session,
                                title: statsVM.resolveTitle(for: session.documentId)
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: - Today Page

    private var todayPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Today section
            VStack(alignment: .leading, spacing: 12) {
                Text("Today")
                    .font(.hedvigLettersSerif(20))

                HStack(spacing: 12) {
                    SummaryStatCard(
                        icon: "clock.fill",
                        iconColor: .blue,
                        value: formatTime(statsVM.todayReadingSeconds),
                        label: "Reading Time"
                    )
                    SummaryStatCard(
                        icon: "text.word.spacing",
                        iconColor: .purple,
                        value: formatWords(statsVM.todayWordsRead),
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
                    value: formatTime(statsVM.statsCache?.totalReadingSeconds ?? 0),
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
                    value: formatWords(statsVM.statsCache?.totalWordsRead ?? 0),
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 40)
    }

    // MARK: - Chart Page

    private var chartPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Daily Reading")
                    .font(.hedvigLettersSerif(20))
                Spacer()
                Picker("Range", selection: $statsVM.chartRange) {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            let barWidth: CGFloat = statsVM.chartRange == .month ? 20 : 40
            let chartWidth = CGFloat(statsVM.dailyReadingData.count) * barWidth

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    Chart(statsVM.dailyReadingData) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Minutes", point.totalMinutes)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: statsVM.chartRange == .month ? 3 : 1)) { _ in
                            if statsVM.chartRange == .week {
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            } else {
                                AxisValueLabel(format: .dateTime.day())
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let minutes = value.as(Double.self) {
                                    Text("\(Int(minutes))m")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(width: max(chartWidth, UIScreen.main.bounds.width - 48), height: 200)
                    .id("chartEnd")
                }
                .onAppear {
                    proxy.scrollTo("chartEnd", anchor: .trailing)
                }
                .onChange(of: statsVM.chartRange) { _, _ in
                    proxy.scrollTo("chartEnd", anchor: .trailing)
                }
            }

            // Average stats summary
            if let cache = statsVM.statsCache {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Averages")
                        .font(.rethinkSans(14, weight: .medium))

                    HStack(spacing: 12) {
                        SummaryStatCard(
                            icon: "clock.fill",
                            iconColor: .blue,
                            value: formatTime(cache.totalReadingSeconds / max(cache.daysRead, 1)),
                            label: "Per Day"
                        )
                        SummaryStatCard(
                            icon: "speedometer",
                            iconColor: .green,
                            value: "\(cache.lifetimeAvgWPM)",
                            label: "Avg WPM"
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 40)
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: Int) -> String {
        if seconds == 0 { return "0m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }

    private func formatWords(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 100_000 { return String(format: "%.1fk", Double(count) / 1000.0) }
        if count < 1_000_000 { return "\(count / 1000)k" }
        return String(format: "%.1fM", Double(count) / 1_000_000.0)
    }
}
