import SwiftUI

struct SpritzModeView: View {
    @ObservedObject var viewModel: ReadingViewModel
    let fontSize: CGFloat

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    Spacer()
                    // Current word with ORP (Optimal Recognition Point)
                    ORPWordView(
                        word: viewModel.currentWord,
                        orpIndex: viewModel.getORPIndex(for: viewModel.currentWord),
                        fontSize: fontSize
                    )
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

struct ORPWordView: View {
    let word: String
    let orpIndex: Int
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(.system(size: fontSize, weight: .medium, design: .serif))
                    .foregroundColor(index == orpIndex ? .red : .primary)
            }
        }
    }
}

#Preview {
    let vm = ReadingViewModel()

    return VStack {
        SpritzModeView(viewModel: vm, fontSize: 32)
    }
    .onAppear {
        vm.loadContent(
            words: ["The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"],
            chapters: [],
            startPosition: ReadingPosition(wordIndex: 4)
        )
    }
}
