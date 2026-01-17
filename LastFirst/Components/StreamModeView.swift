import SwiftUI

struct StreamModeView: View {
    @ObservedObject var viewModel: ReadingViewModel
    let fontSize: CGFloat
    let screenWidth: CGFloat
    let availableHeight: CGFloat

    var body: some View {
        let streamData = viewModel.getStreamLines(
            screenWidth: screenWidth,
            fontSize: fontSize,
            availableHeight: availableHeight
        )
        
        GeometryReader { geometry in
            VStack(spacing: 4) {
                ForEach(Array(streamData.lines.enumerated()), id: \.offset) { lineIndex, line in
                    let isCurrentLine = lineIndex == streamData.currentLineIndex
                    let opacity = calculateOpacity(
                        lineIndex: lineIndex,
                        currentLineIndex: streamData.currentLineIndex,
                        totalLines: streamData.lines.count
                    )
                    
                    HStack(spacing: 0) {
                        // For current line, show words up to current word
                        if isCurrentLine {
                            ForEach(Array(line.enumerated()), id: \.offset) { wordIndex, word in
                                if wordIndex <= streamData.wordIndexInLine {
                                    Text(word + " ")
                                        .font(.system(size: fontSize, weight: .regular, design: .serif))
                                        .foregroundColor(.primary)
                                }
                            }
                        } else if lineIndex < streamData.currentLineIndex {
                            // Lines above current: show all words
                            Text(line.joined(separator: " "))
                                .font(.system(size: fontSize, weight: .regular, design: .serif))
                                .foregroundColor(.primary.opacity(opacity))
                        }
                        // Lines below current: don't show yet
                        Spacer()
                    }
                    .frame(height: fontSize * 1.4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.1), value: viewModel.currentWordIndex)
        }
        .onAppear {
            viewModel.initializeStreamMode()
        }
        .onChange(of: viewModel.readingMode) { _, newMode in
            if newMode == .stream {
                viewModel.initializeStreamMode()
            }
        }
    }
    
    private func calculateOpacity(lineIndex: Int, currentLineIndex: Int, totalLines: Int) -> Double {
        let distance = abs(lineIndex - currentLineIndex)
        if distance == 0 {
            return 1.0
        }
        // Fade out lines above current line
        let maxDistance = Double(max(1, currentLineIndex))
        let normalizedDistance = Double(distance) / maxDistance
        return max(0.3, 1.0 - (normalizedDistance * 0.5))
    }
}

#Preview {
    let vm = ReadingViewModel()

    return GeometryReader { geometry in
        StreamModeView(
            viewModel: vm,
            fontSize: 24,
            screenWidth: geometry.size.width,
            availableHeight: 200
        )
        .background(Color.gray.opacity(0.1))
    }
    .onAppear {
        let text = "The quick brown fox jumps over the lazy dog. A wonderful serenity has taken possession of my entire soul."
        vm.loadContent(
            words: text.components(separatedBy: " "),
            chapters: [],
            startPosition: ReadingPosition(wordIndex: 0)
        )
        vm.readingMode = .stream
    }
}
