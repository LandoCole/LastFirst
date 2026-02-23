import SwiftUI

struct ReaderScrollView: View {
    @ObservedObject var viewModel: ReadingViewModel
    let fontSize: CGFloat
    var topContentInset: CGFloat = 16
    var theme: ResolvedReaderTheme? = nil
    let onWordTapped: (Int) -> Void
    var onScrollDirectionHide: (() -> Void)? = nil
    var onScrollDirectionShow: (() -> Void)? = nil
    var browseControlsVisible: Bool = true

    @State private var previousScrollOffset: CGFloat? = nil
    @State private var scrollDirectionTask: Task<Void, Never>? = nil
    @State private var currentScrollDirection: Int = 0  // -1 = down, 1 = up, 0 = none

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                let themeMargin = CGFloat(theme?.definition.margin ?? 24)
                let lineHeight = fontSize * CGFloat(theme?.definition.lineSpacing ?? 1.6)
                let pausedDisplay = viewModel.getPausedDisplayLines(
                    screenWidth: geometry.size.width,
                    fontSize: fontSize,
                    horizontalPadding: themeMargin * 2,
                    wordSpacing: CGFloat(theme?.definition.wordSpacing ?? 0),
                    letterSpacing: CGFloat(theme?.definition.letterSpacing ?? 0)
                )

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(pausedDisplay.lines) { line in
                            pausedLineView(line: line, fontSize: fontSize, lineHeight: lineHeight, themeMargin: themeMargin)
                        }
                    }
                    .padding(.horizontal, themeMargin)
                    .padding(.top, topContentInset)
                    .padding(.bottom, 240)
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: contentGeometry.frame(in: .named("pausedScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "pausedScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                    handleScrollDirection(newOffset)
                }
                .onChange(of: browseControlsVisible) { _, _ in
                    previousScrollOffset = nil
                    currentScrollDirection = 0
                    scrollDirectionTask?.cancel()
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(pausedDisplay.currentLineId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Block-Aware Line Views

    @ViewBuilder
    private func pausedLineView(line: ReadingViewModel.PausedDisplayLine, fontSize: CGFloat, lineHeight: CGFloat, themeMargin: CGFloat) -> some View {
        switch line.kind {
        case .blank:
            Color.clear
                .frame(height: fontSize * CGFloat((theme?.definition.lineSpacing ?? 1.6) * 0.56))
                .id(line.id)

        case .title(let title, let kind):
            Text(title)
                .font(.system(size: fontSize + 4, weight: kind == .chapterTitle ? ((theme?.definition.bold ?? false) ? .bold : .semibold) : ((theme?.definition.bold ?? false) ? .semibold : .medium), design: theme?.fontDesign ?? .serif))
                .tracking(fontSize * CGFloat(theme?.definition.letterSpacing ?? 0))
                .foregroundColor(theme?.textColor ?? .primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .id(line.id)

        case .text(let words):
            HStack(spacing: fontSize * CGFloat(theme?.definition.wordSpacing ?? 0)) {
                ForEach(words) { w in
                    WordButton(
                        word: w.text,
                        isCurrentWord: w.wordIndex == viewModel.currentWordIndex,
                        fontSize: fontSize,
                        theme: theme,
                        onTap: {
                            onWordTapped(w.wordIndex)
                        }
                    )
                }
                Spacer()
            }
            .frame(minHeight: lineHeight)
            .id(line.id)

        case .listItem(let words, let bullet):
            HStack(alignment: .top, spacing: 6) {
                Text(bullet)
                    .font(.system(size: fontSize, weight: theme?.swiftUIFontWeight ?? .regular, design: theme?.fontDesign ?? .serif))
                    .foregroundColor(theme?.secondaryTextColor ?? .secondary)
                HStack(spacing: fontSize * CGFloat(theme?.definition.wordSpacing ?? 0)) {
                    ForEach(words) { w in
                        WordButton(
                            word: w.text,
                            isCurrentWord: w.wordIndex == viewModel.currentWordIndex,
                            fontSize: fontSize,
                            theme: theme,
                            onTap: { onWordTapped(w.wordIndex) }
                        )
                    }
                    Spacer()
                }
            }
            .padding(.leading, 12)
            .frame(minHeight: lineHeight)
            .id(line.id)

        case .blockquote(let words):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill((theme?.secondaryTextColor ?? .secondary).opacity(0.5))
                    .frame(width: 3)
                HStack(spacing: fontSize * CGFloat(theme?.definition.wordSpacing ?? 0)) {
                    ForEach(words) { w in
                        WordButton(
                            word: w.text,
                            isCurrentWord: w.wordIndex == viewModel.currentWordIndex,
                            fontSize: fontSize,
                            theme: theme,
                            onTap: { onWordTapped(w.wordIndex) }
                        )
                    }
                    Spacer()
                }
                .padding(.leading, 10)
            }
            .padding(.leading, 8)
            .frame(minHeight: lineHeight)
            .id(line.id)

        case .codeBlock(let code):
            Text(code)
                .font(.system(size: fontSize - 2, weight: theme?.swiftUIFontWeight ?? .regular, design: .monospaced))
                .foregroundColor((theme?.textColor ?? .primary).opacity(0.9))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill((theme?.textColor ?? .primary).opacity(0.05))
                )
                .id(line.id)

        case .image(let altText):
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .foregroundColor(theme?.secondaryTextColor ?? .secondary)
                Text(altText)
                    .font(.system(size: fontSize - 1, weight: .regular, design: theme?.fontDesign ?? .serif))
                    .italic()
                    .foregroundColor(theme?.secondaryTextColor ?? .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .id(line.id)
        }
    }

    private func handleScrollDirection(_ offset: CGFloat) {
        guard let prev = previousScrollOffset else {
            previousScrollOffset = offset
            return
        }

        let delta = offset - prev
        previousScrollOffset = offset

        // Ignore tiny movements (< 1pt)
        guard abs(delta) > 1 else { return }

        // delta > 0 means content moved down → user scrolled UP (showing earlier content)
        // delta < 0 means content moved up → user scrolled DOWN (reading forward)
        let direction = delta > 0 ? 1 : -1

        if direction != currentScrollDirection {
            // Direction changed — cancel pending timer, start new one
            currentScrollDirection = direction
            scrollDirectionTask?.cancel()

            let threshold: UInt64 = direction == -1 ? 300_000_000 : 200_000_000  // 300ms down, 200ms up

            scrollDirectionTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: threshold)
                } catch { return }

                if direction == -1 && browseControlsVisible {
                    onScrollDirectionHide?()
                } else if direction == 1 && !browseControlsVisible {
                    onScrollDirectionShow?()
                }
            }
        }
    }
}

struct WordButton: View {
    let word: String
    let isCurrentWord: Bool
    let fontSize: CGFloat
    var theme: ResolvedReaderTheme? = nil
    let onTap: () -> Void

    var body: some View {
        let textColor = theme?.textColor ?? .primary
        let fontDesign = theme?.fontDesign ?? .serif
        let baseWeight: Font.Weight = theme?.swiftUIFontWeight ?? .regular
        let highlightWeight: Font.Weight = (theme?.definition.bold ?? false) ? .heavy : .bold

        Button(action: onTap) {
            Text(word + " ")
                .font(.system(size: fontSize, weight: isCurrentWord ? highlightWeight : baseWeight, design: fontDesign))
                .tracking(fontSize * CGFloat(theme?.definition.letterSpacing ?? 0))
                .foregroundColor(isCurrentWord ? textColor : textColor.opacity(0.6))
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    isCurrentWord ?
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.yellow.opacity(0.3)) :
                    nil
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Flow layout for wrapping words
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.width ?? 0,
            spacing: spacing,
            subviews: subviews
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            spacing: spacing,
            subviews: subviews
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            ), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, spacing: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

#Preview {
    let vm = ReadingViewModel()

    return ReaderScrollView(
        viewModel: vm,
        fontSize: 24,
        onWordTapped: { index in
            vm.goToWord(at: index)
        }
    )
    .onAppear {
        let text = "The quick brown fox jumps over the lazy dog. A wonderful serenity has taken possession of my entire soul."
        let tokens = text.components(separatedBy: " ").enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        vm.loadContent(tokens: tokens, chapters: [], startTokenIndex: 5)
    }
}
