import SwiftUI
import Charts

struct ReadingStatsSheet: View {
    @ObservedObject var statsVM: ReadingStatsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    todaySection
                    Divider().padding(.horizontal, 20)
                    summaryGrid
                    dailyChart
                    recentSessionsList
                }
                .padding(.vertical, 16)
            }
            .task { await statsVM.load() }
            .navigationTitle("Reading Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Today Section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.hedvigLettersSerif(20))
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                SummaryStatCard(
                    icon: "clock.fill",
                    iconColor: .blue,
                    value: formatReadingTime(statsVM.todayReadingSeconds),
                    label: "Reading Time"
                )
                SummaryStatCard(
                    icon: "text.word.spacing",
                    iconColor: .purple,
                    value: formatWordsCompact(statsVM.todayWordsRead),
                    label: "Words Read"
                )
            }
            .padding(.horizontal, 20)

            if !statsVM.todaySessions.isEmpty {
                Text("Sessions")
                    .font(.rethinkSans(14, weight: .medium))
                    .padding(.horizontal, 20)
                ForEach(statsVM.todaySessions, id: \.id) { session in
                    SessionRow(session: session, title: statsVM.resolveTitle(for: session.documentId))
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
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
                value: formatReadingTime(statsVM.statsCache?.totalReadingSeconds ?? 0),
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
                value: formatWordsCompact(statsVM.statsCache?.totalWordsRead ?? 0),
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
        .padding(.horizontal, 20)
    }

    // MARK: - Daily Chart

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .padding(.horizontal, 20)

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
                    .frame(width: max(chartWidth, UIScreen.main.bounds.width - 40), height: 180)
                    .id("chartEnd")
                }
                .onAppear {
                    proxy.scrollTo("chartEnd", anchor: .trailing)
                }
                .onChange(of: statsVM.chartRange) { _, _ in
                    proxy.scrollTo("chartEnd", anchor: .trailing)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Recent Sessions

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.hedvigLettersSerif(20))
                .padding(.horizontal, 20)

            if statsVM.recentSessions.isEmpty {
                Text("No sessions yet")
                    .font(.rethinkSans(14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(statsVM.recentSessions, id: \.id) { session in
                        SessionRow(session: session, title: statsVM.resolveTitle(for: session.documentId))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Formatting

    private func formatReadingTime(_ seconds: Int) -> String {
        if seconds == 0 { return "0m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }

    private func formatWordsCompact(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 100_000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk", k)
        }
        if count < 1_000_000 {
            return "\(count / 1000)k"
        }
        let m = Double(count) / 1_000_000.0
        return String(format: "%.1fM", m)
    }
}

// MARK: - SummaryStatCard

struct SummaryStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.rethinkSans(22, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.rethinkSans(12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - SessionRow

struct SessionRow: View {
    let session: ReadingSessionRecord
    let title: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rethinkSans(14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(session.startedAt, style: .relative)
                    .font(.rethinkSans(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(session.durationSeconds))
                    .font(.rethinkSans(14, weight: .medium))
                    .foregroundStyle(.primary)
                Text("\(session.averageWPM) wpm")
                    .font(.rethinkSans(12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "<1m" }
        let m = seconds / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }
}
