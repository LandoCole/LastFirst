import SwiftUI

struct ScanModeView: View {
    @ObservedObject var viewModel: ReadingViewModel
    let fontSize: CGFloat
    let screenWidth: CGFloat
    let availableHeight: CGFloat

    var body: some View {
        let scanData = viewModel.getLinesForScanMode(
            screenWidth: screenWidth,
            fontSize: fontSize,
            availableHeight: availableHeight
        )

        VStack(spacing: 4) {
            ForEach(Array(scanData.lines.enumerated()), id: \.offset) { lineIndex, line in
                let isCurrentLine = lineIndex == scanData.currentLineIndex
                let opacity = calculateOpacity(lineIndex: lineIndex, currentLineIndex: scanData.currentLineIndex, totalLines: scanData.lines.count)

                HStack(spacing: 0) {
                    ForEach(Array(line.enumerated()), id: \.offset) { wordIndex, word in
                        let isCurrentWord = isCurrentLine && wordIndex == scanData.wordIndexInLine
                        Text(word + " ")
                            .font(.system(size: fontSize, weight: isCurrentWord ? .bold : .regular, design: .serif))
                            .foregroundColor(isCurrentWord ? .primary : .primary.opacity(opacity))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer()
                }
                .frame(height: fontSize * 1.4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calculateOpacity(lineIndex: Int, currentLineIndex: Int, totalLines: Int) -> Double {
        let distance = abs(lineIndex - currentLineIndex)
        if distance == 0 {
            return 1.0
        }
        // Fade out based on distance from current line
        let maxDistance = Double(max(currentLineIndex, totalLines - currentLineIndex - 1))
        if maxDistance == 0 { return 0.5 }
        let normalizedDistance = Double(distance) / maxDistance
        return max(0.3, 1.0 - (normalizedDistance * 0.5))
    }
}

#Preview {
    let vm = ReadingViewModel()

    return GeometryReader { geometry in
        ScanModeView(
            viewModel: vm,
            fontSize: 20,
            screenWidth: geometry.size.width,
            availableHeight: 300
        )
        .padding()
    }
    .onAppear {
        let text = "The quick brown fox jumps over the lazy dog. A wonderful serenity has taken possession of my entire soul, like these sweet mornings of spring which I enjoy with my whole heart. I am alone, and feel the charm of existence in this spot."
        vm.loadContent(
            words: text.components(separatedBy: " "),
            chapters: [],
            startPosition: ReadingPosition(wordIndex: 15)
        )
        vm.readingMode = .scan
    }
}
