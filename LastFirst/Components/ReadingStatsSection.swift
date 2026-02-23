import SwiftUI

struct ReadingStatsSection: View {
    @ObservedObject var statsVM: ReadingStatsViewModel
    @Binding var showStatsSheet: Bool

    private var hasData: Bool {
        !statsVM.recentSessions.isEmpty || (statsVM.statsCache?.totalReadingSeconds ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button { showStatsSheet = true } label: {
                HStack {
                    Text("Your Reading")
                        .font(.hedvigLettersSerif(20))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            if hasData {
                HStack(spacing: 12) {
                    StatMiniCard(
                        icon: "flame.fill",
                        value: "\(statsVM.statsCache?.currentStreak ?? 0)",
                        label: "Day Streak",
                        tintColor: .orange
                    )
                    StatMiniCard(
                        icon: "clock.fill",
                        value: formatReadingTimeShort(statsVM.todayReadingSeconds),
                        label: "Today",
                        tintColor: .blue
                    )
                    StatMiniCard(
                        icon: "speedometer",
                        value: "\(statsVM.todayWPM)",
                        label: "Avg WPM",
                        tintColor: .green
                    )
                }
                .padding(.horizontal, 20)
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("Start reading to see your stats")
                            .font(.rethinkSans(13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
            }
        }
    }

    private func formatReadingTimeShort(_ seconds: Int) -> String {
        if seconds < 60 { return "<1m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }
}

// MARK: - StatMiniCard

private struct StatMiniCard: View {
    let icon: String
    let value: String
    let label: String
    let tintColor: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tintColor)
            Text(value)
                .font(.rethinkSans(20, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.rethinkSans(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
