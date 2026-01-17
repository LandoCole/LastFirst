import SwiftUI

struct PausedScrollView: View {
    @ObservedObject var viewModel: ReadingViewModel
    let fontSize: CGFloat
    let onWordTapped: (Int) -> Void

    @State private var scrollOffset: CGFloat = 0

    private let wordsPerChunk = 50

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(wordChunks.indices, id: \.self) { chunkIndex in
                            let chunk = wordChunks[chunkIndex]
                            FlowLayout(spacing: 4) {
                                ForEach(Array(chunk.enumerated()), id: \.offset) { localIndex, word in
                                    let globalIndex = chunkIndex * wordsPerChunk + localIndex
                                    WordButton(
                                        word: word,
                                        isCurrentWord: globalIndex == viewModel.currentWordIndex,
                                        fontSize: fontSize,
                                        onTap: {
                                            onWordTapped(globalIndex)
                                        }
                                    )
                                    .id(globalIndex)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onAppear {
                    // Scroll to current word
                    withAnimation {
                        scrollProxy.scrollTo(viewModel.currentWordIndex, anchor: .center)
                    }
                }
                .onChange(of: viewModel.currentWordIndex) { _, newIndex in
                    withAnimation {
                        scrollProxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private var wordChunks: [[String]] {
        stride(from: 0, to: viewModel.words.count, by: wordsPerChunk).map { startIndex in
            let endIndex = min(startIndex + wordsPerChunk, viewModel.words.count)
            return Array(viewModel.words[startIndex..<endIndex])
        }
    }
}

struct WordButton: View {
    let word: String
    let isCurrentWord: Bool
    let fontSize: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(word)
                .font(.system(size: fontSize * 0.7, design: .serif))
                .foregroundColor(isCurrentWord ? .primary : .gray)
                .fontWeight(isCurrentWord ? .semibold : .regular)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
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

    return PausedScrollView(
        viewModel: vm,
        fontSize: 24,
        onWordTapped: { index in
            vm.goToWord(at: index)
        }
    )
    .onAppear {
        let text = "The quick brown fox jumps over the lazy dog. A wonderful serenity has taken possession of my entire soul."
        vm.loadContent(
            words: text.components(separatedBy: " "),
            chapters: [],
            startPosition: ReadingPosition(wordIndex: 5)
        )
    }
}
