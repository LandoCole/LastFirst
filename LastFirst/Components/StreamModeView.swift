import SwiftUI

struct StreamModeView: View {
    @ObservedObject var viewModel: ReadingViewModel
    let theme: ResolvedReaderTheme
    let screenWidth: CGFloat
    let availableHeight: CGFloat

    var body: some View {
        let streamData = viewModel.getStreamLines(
            screenWidth: screenWidth,
            fontSize: theme.fontSize,
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
                            if line.isBlank {
                                Color.clear
                                    .frame(height: theme.fontSize * 0.9)
                            } else {
                                let fontDesign = lineDesign(for: line)
                                let fontWeight = lineWeight(for: line)
                                ForEach(Array(line.words.enumerated()), id: \.offset) { wordIndex, word in
                                    if wordIndex <= streamData.wordIndexInLine {
                                        let isCurrentWord = wordIndex == streamData.wordIndexInLine
                                        let isBreathWord = viewModel.isInParagraphBreath && isCurrentWord
                                        Text(word + " ")
                                            .font(.system(size: lineFontSize(for: line), weight: isCurrentWord ? .bold : fontWeight, design: fontDesign))
                                            .foregroundColor(theme.textColor)
                                            .underline(isBreathWord, color: theme.textColor)
                                            .italic(line.blockKind == .quote)
                                    }
                                }
                            }
                        } else if lineIndex < streamData.currentLineIndex {
                            // Lines above current: show all words
                            if line.isBlank {
                                Color.clear
                                    .frame(height: theme.fontSize * 0.9)
                            } else {
                                streamLineContent(line: line, opacity: opacity)
                            }
                        }
                        // Lines below current: don't show yet
                        Spacer()
                    }
                    .frame(height: theme.fontSize * 1.4)
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

    // MARK: - Block-Aware Helpers

    private func lineFontSize(for line: ReadingViewModel.WrappedLine) -> CGFloat {
        switch line.blockKind {
        case .heading: return theme.fontSize + 4
        case .code: return theme.fontSize - 2
        default: return theme.fontSize
        }
    }

    private func lineDesign(for line: ReadingViewModel.WrappedLine) -> Font.Design {
        switch line.blockKind {
        case .code: return .monospaced
        default: return theme.fontDesign
        }
    }

    private func lineWeight(for line: ReadingViewModel.WrappedLine) -> Font.Weight {
        switch line.blockKind {
        case .heading: return .semibold
        default: return theme.swiftUIFontWeight
        }
    }

    @ViewBuilder
    private func streamLineContent(line: ReadingViewModel.WrappedLine, opacity: Double) -> some View {
        switch line.blockKind {
        case .heading:
            Text(line.words.joined(separator: " "))
                .font(.system(size: theme.fontSize + 4, weight: .semibold, design: theme.fontDesign))
                .foregroundColor(theme.textColor.opacity(opacity))
        case .listItem:
            HStack(alignment: .top, spacing: 4) {
                Text("•")
                    .foregroundColor(theme.secondaryTextColor.opacity(opacity))
                Text(line.words.joined(separator: " "))
                    .font(.system(size: theme.fontSize, weight: theme.swiftUIFontWeight, design: theme.fontDesign))
                    .foregroundColor(theme.textColor.opacity(opacity))
            }
            .padding(.leading, 12)
        case .quote:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.secondaryTextColor.opacity(opacity * 0.5))
                    .frame(width: 3)
                Text(line.words.joined(separator: " "))
                    .font(.system(size: theme.fontSize, weight: theme.swiftUIFontWeight, design: theme.fontDesign))
                    .italic()
                    .foregroundColor(theme.textColor.opacity(opacity))
                    .padding(.leading, 10)
            }
            .padding(.leading, 8)
        case .code:
            Text(line.words.joined(separator: " "))
                .font(.system(size: theme.fontSize - 2, weight: theme.swiftUIFontWeight, design: .monospaced))
                .foregroundColor(theme.textColor.opacity(opacity))
        default:
            Text(line.words.joined(separator: " "))
                .font(.system(size: theme.fontSize, weight: theme.swiftUIFontWeight, design: theme.fontDesign))
                .foregroundColor(theme.textColor.opacity(opacity))
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
    let theme = ReaderThemeSettings().resolvedTheme(
        appearanceMode: .system,
        systemScheme: .light,
        fontSize: 24
    )

    return GeometryReader { geometry in
        StreamModeView(
            viewModel: vm,
            theme: theme,
            screenWidth: geometry.size.width,
            availableHeight: 200
        )
        .background(Color.gray.opacity(0.1))
    }
    .onAppear {
        let text = "The quick brown fox jumps over the lazy dog. A wonderful serenity has taken possession of my entire soul."
        let tokens = text.components(separatedBy: " ").enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        vm.loadContent(tokens: tokens, chapters: [], startTokenIndex: 0)
        vm.readingMode = .stream
    }
}
