import SwiftUI

struct SpritzModeView: View {
    @ObservedObject var viewModel: ReadingViewModel
    let theme: ResolvedReaderTheme

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    Spacer()
                    // Current word with ORP (Optimal Recognition Point)
                    let currentToken = currentTokenKind
                    if currentToken == .footnoteRef {
                        // Footnote reference — display in superscript style
                        Text(viewModel.currentWord)
                            .font(.system(size: theme.fontSize * 0.7, weight: .bold, design: theme.fontDesign))
                            .foregroundColor(.blue)
                            .baselineOffset(theme.fontSize * 0.3)
                    } else {
                        ORPWordView(
                            word: viewModel.currentWord,
                            orpIndex: viewModel.getORPIndex(for: viewModel.currentWord),
                            theme: theme,
                            isUnderlined: viewModel.isInParagraphBreath
                        )
                    }
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private var currentTokenKind: TokenKind {
        let wordIndex = viewModel.currentWordIndex
        // Find the token corresponding to this word
        guard wordIndex < viewModel.tokens.count else { return .word }
        // Walk tokens to find the one at this word position
        var wordCount = 0
        for token in viewModel.tokens {
            if token.kind == .word || token.kind == .footnoteRef {
                if wordCount == wordIndex {
                    return token.kind
                }
                wordCount += 1
            }
        }
        return .word
    }
}

struct ORPWordView: View {
    let word: String
    let orpIndex: Int
    let theme: ResolvedReaderTheme
    let isUnderlined: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(.system(size: theme.fontSize, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(index == orpIndex ? .red : theme.textColor)
            }
        }
        .overlay(alignment: .bottom) {
            if isUnderlined {
                Rectangle()
                    .fill(theme.textColor)
                    .frame(height: 2)
                    .offset(y: 6)
            }
        }
    }
}

#Preview {
    let vm = ReadingViewModel()
    let theme = ReaderThemeSettings().resolvedTheme(
        appearanceMode: .system,
        systemScheme: .light,
        fontSize: 32
    )

    return VStack {
        SpritzModeView(viewModel: vm, theme: theme)
    }
    .onAppear {
        let words = ["The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"]
        let tokens = words.enumerated().map { idx, w in
            Token(id: idx, text: w, kind: .word, blockIndex: 0, sentenceIndex: 0, sourceLocation: nil)
        }
        vm.loadContent(tokens: tokens, chapters: [], startTokenIndex: 4)
    }
}
