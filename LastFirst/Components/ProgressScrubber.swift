import SwiftUI

struct ProgressScrubber: View {
    @ObservedObject var viewModel: ReadingViewModel
    var theme: ResolvedReaderTheme? = nil
    var onScrub: ((Double) -> Void)?

    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0
    @State private var showChapterProgress: Bool = true
    @State private var lastSnappedChapterIndex: Int? = nil
    @State private var dragChapterTitle: String? = nil

    var body: some View {
        let textColor = theme?.textColor ?? .primary
        let secondaryColor = theme?.secondaryTextColor ?? .secondary

        VStack(spacing: 4) {
            // Chapter title + toggle button
            HStack {
                Text(isDragging && !showChapterProgress ? (dragChapterTitle ?? currentChapterTitle) : currentChapterTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.15), value: dragChapterTitle)

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChapterProgress.toggle()
                    }
                }) {
                    Image(systemName: showChapterProgress ? "book" : "list.bullet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(secondaryColor)
                        .frame(width: 36, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Progress bar
            GeometryReader { geometry in
                let width = geometry.size.width
                let effectiveProgress: Double = {
                    if isDragging { return dragProgress }
                    return showChapterProgress ? viewModel.chapterProgress : viewModel.progress
                }()
                let fillWidth = effectiveProgress * width

                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(secondaryColor.opacity(0.2))
                        .frame(height: 6)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(textColor.opacity(0.5))
                        .frame(width: max(0, fillWidth), height: 6)

                    // Chapter tick marks (only in total mode)
                    if !showChapterProgress {
                        ForEach(viewModel.chapters) { chapter in
                            let chapterProgress = viewModel.words.isEmpty ? 0 : Double(chapter.startWordIndex) / Double(max(1, viewModel.words.count))
                            let tickX = chapterProgress * width

                            Rectangle()
                                .fill(secondaryColor.opacity(0.4))
                                .frame(width: 1, height: 6)
                                .offset(x: tickX)
                        }
                    }
                }
                .frame(height: 6)
                .contentShape(Rectangle().inset(by: -10))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let rawProgress = max(0, min(1, value.location.x / width))

                            if !showChapterProgress {
                                // Total mode: snap to chapter starts during drag
                                let targetWordIndex = Int(rawProgress * Double(max(1, viewModel.words.count - 1)))
                                let snapped = snapToChapterIfClose(wordIndex: targetWordIndex, totalWords: viewModel.words.count)

                                if snapped != targetWordIndex {
                                    // Snapped to a chapter — find which one
                                    let chapterIdx = viewModel.chapters.firstIndex(where: { $0.startWordIndex == snapped })
                                    if chapterIdx != lastSnappedChapterIndex {
                                        lastSnappedChapterIndex = chapterIdx
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                    }
                                    dragProgress = Double(snapped) / Double(max(1, viewModel.words.count - 1))
                                } else {
                                    lastSnappedChapterIndex = nil
                                    dragProgress = rawProgress
                                }

                                // Update live chapter title
                                let lookupIndex = snapped != targetWordIndex ? snapped : targetWordIndex
                                let chapter = viewModel.chapters.last(where: { $0.startWordIndex <= lookupIndex })
                                dragChapterTitle = chapter?.title
                            } else {
                                dragProgress = rawProgress
                            }
                        }
                        .onEnded { value in
                            isDragging = false
                            lastSnappedChapterIndex = nil
                            dragChapterTitle = nil
                            let finalProgress = max(0, min(1, value.location.x / width))

                            if !showChapterProgress {
                                // Total mode: snap to nearest chapter start
                                let targetWordIndex = Int(finalProgress * Double(max(1, viewModel.words.count - 1)))
                                let snapped = snapToChapterIfClose(wordIndex: targetWordIndex, totalWords: viewModel.words.count)
                                if snapped != targetWordIndex {
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }
                                viewModel.goToWord(at: snapped)
                            } else {
                                viewModel.setProgress(finalProgress, chapterMode: true)
                            }
                            onScrub?(finalProgress)
                        }
                )
            }
            .frame(height: 6)

            // Bottom labels: percentage + time remaining
            HStack {
                Spacer()

                let displayProgress = isDragging ? dragProgress : (showChapterProgress ? viewModel.chapterProgress : viewModel.progress)
                Text("\(Int(displayProgress * 100))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(secondaryColor)

                if viewModel.effectiveWPM > 0 {
                    let minutesRemaining: Double = {
                        if showChapterProgress {
                            return viewModel.chapterTimeRemaining / 60.0
                        } else {
                            let remainingWords = max(0, viewModel.words.count - viewModel.currentWordIndex)
                            return Double(remainingWords) / Double(viewModel.effectiveWPM)
                        }
                    }()
                    Text(formatTimeRemaining(minutesRemaining))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(secondaryColor)
                }
            }
        }
        .frame(height: 46)
    }

    private var currentChapterTitle: String {
        guard !viewModel.chapters.isEmpty else { return "" }
        let chapter = viewModel.chapters.last(where: { $0.startWordIndex <= viewModel.currentWordIndex })
        return chapter?.title ?? viewModel.chapters.first?.title ?? ""
    }

    private func snapToChapterIfClose(wordIndex: Int, totalWords: Int) -> Int {
        let snapThreshold = max(1, totalWords / 50) // ~2% of book
        for chapter in viewModel.chapters {
            if abs(wordIndex - chapter.startWordIndex) < snapThreshold {
                return chapter.startWordIndex
            }
        }
        return wordIndex
    }

    private func formatTimeRemaining(_ minutes: Double) -> String {
        if minutes < 1 {
            return "<1 min left"
        } else if minutes < 60 {
            return "\(Int(minutes)) min left"
        } else {
            let hours = Int(minutes / 60)
            let mins = Int(minutes) % 60
            return "\(hours)h \(mins)m left"
        }
    }
}
