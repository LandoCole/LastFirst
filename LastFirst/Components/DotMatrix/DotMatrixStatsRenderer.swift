import UIKit

struct StatDisplay {
    let value: String
    let label: String
    let accentColor: UIColor?
}

@MainActor
struct DotMatrixStatsRenderer {

    // MARK: - Generate Displays from ViewModel

    static func generateStatDisplays(from statsVM: ReadingStatsViewModel) -> [StatDisplay] {
        let todayMinutes = statsVM.todayReadingSeconds / 60

        let streak = statsVM.statsCache?.currentStreak ?? 0
        let wpm = statsVM.todayWPM
        let totalWords = statsVM.statsCache?.totalWordsRead ?? 0

        return [
            StatDisplay(
                value: "\(todayMinutes)",
                label: "MIN TODAY",
                accentColor: nil
            ),
            StatDisplay(
                value: "\(streak)",
                label: "STREAK",
                accentColor: nil
            ),
            StatDisplay(
                value: "\(wpm)",
                label: "WPM",
                accentColor: nil
            ),
            StatDisplay(
                value: formatCompact(totalWords),
                label: "WORDS",
                accentColor: nil
            )
        ]
    }

    // MARK: - Render Stat → DotFrame

    static func renderStatToFrame(_ stat: StatDisplay) -> DotFrame {
        var frame = DotFrame()
        let gridSize = DotFrame.gridSize
        let litPixel = DotPixel.lit

        // Render value (large font) — centered horizontally, positioned around row 18
        let valueWidth = DotMatrixFonts.measureWidth(stat.value, font: .large)
        let valueOriginCol = max(0, (gridSize - valueWidth) / 2)
        let valueOriginRow = 18

        let valueLitPixels = DotMatrixFonts.renderString(
            stat.value,
            font: .large,
            origin: (col: valueOriginCol, row: valueOriginRow)
        )

        for pixel in valueLitPixels {
            frame[pixel.col, pixel.row] = litPixel
        }

        // Render label (small font) — centered horizontally, positioned around row 38
        let labelWidth = DotMatrixFonts.measureWidth(stat.label, font: .small)
        let labelOriginCol = max(0, (gridSize - labelWidth) / 2)
        let labelOriginRow = 38

        let labelLitPixels = DotMatrixFonts.renderString(
            stat.label,
            font: .small,
            origin: (col: labelOriginCol, row: labelOriginRow)
        )

        let labelColor = UIColor(white: 0.45, alpha: 1.0)
        let labelPixel = DotPixel(radius: 0.7, color: labelColor)

        for pixel in labelLitPixels {
            frame[pixel.col, pixel.row] = labelPixel
        }

        return frame
    }

    // MARK: - Compact Number Formatting

    static func formatCompact(_ value: Int) -> String {
        if value >= 1_000_000 {
            let m = Double(value) / 1_000_000.0
            if m >= 10 {
                return "\(Int(m))M"
            }
            return String(format: "%.1fM", m).replacingOccurrences(of: ".0M", with: "M")
        } else if value >= 1_000 {
            let k = Double(value) / 1_000.0
            if k >= 10 {
                return "\(Int(k))K"
            }
            return String(format: "%.1fK", k).replacingOccurrences(of: ".0K", with: "K")
        }
        return "\(value)"
    }
}
