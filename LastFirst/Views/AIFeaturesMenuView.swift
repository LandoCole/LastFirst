import SwiftUI

enum AITextMode: String, CaseIterable, Identifiable {
    case original, optimized, easyRead, quickSummary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original Text"
        case .optimized: return "Optimized Text"
        case .easyRead: return "Easy Read"
        case .quickSummary: return "Quick Summary"
        }
    }

    var description: String {
        switch self {
        case .original:
            return "The unmodified source text, exactly as published."
        case .optimized:
            return "Cleaned and polished for speed reading. Formatting artifacts removed, prose smoothed — meaning fully preserved. Best for PDFs and web imports."
        case .easyRead:
            return "Rewritten in clear, approachable language. Same story, same length — just easier to follow."
        case .quickSummary:
            return "Distilled to the essentials. Everything you need to know, nothing you don't."
        }
    }

    var iconName: String {
        switch self {
        case .original: return "doc.text"
        case .optimized: return "bolt.fill"
        case .easyRead: return "book.fill"
        case .quickSummary: return "text.justify.leading"
        }
    }
}

enum SummaryScope {
    case chapter, entireBook
}

struct AIFeaturesMenuView: View {
    let theme: ResolvedReaderTheme
    let bookTitle: String
    let chapterTitle: String
    let progressPercent: Int
    let activeMode: AITextMode
    let processingMode: AITextMode?
    let readyModes: Set<AITextMode>
    let onSelectMode: (AITextMode, SummaryScope?) -> Void
    let onRecapSession: () -> Void

    @State private var expandedQuickSummary = false
    @State private var expandedEasyRead = false
    @State private var rotatingTextIndex = 0
    @State private var rotationTimer: Timer? = nil

    private let rotatingMessages = [
        "Rearranging the words...",
        "Teaching the text new tricks...",
        "Speed-reading the original first...",
        "Convincing paragraphs to cooperate...",
        "Giving every sentence a pep talk...",
        "Flipping through at 10,000 WPM...",
        "Almost there, just dotting the i's...",
    ]

    var body: some View {
        if let processing = processingMode {
            processingView(mode: processing)
        } else {
            cardScrollView
        }
    }

    private var cardScrollView: some View {
        ScrollView {
            VStack(spacing: 12) {
                contextHeader

                // Mode cards — fixed order, active pill moves
                ForEach(AITextMode.allCases) { mode in
                    switch mode {
                    case .quickSummary:
                        quickSummaryCard(mode: mode)
                    case .easyRead:
                        easyReadCard(mode: mode)
                    default:
                        modeCard(mode: mode)
                    }
                }

                // Recap Recent Session card
                recapCard
            }
            .padding(.horizontal, 22)
            .padding(.top, 0)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Processing Overlay

    private func processingView(mode: AITextMode) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(theme.secondaryTextColor)

            Text(rotatingMessages[rotatingTextIndex])
                .font(.rethinkSans(14, weight: .medium))
                .foregroundColor(theme.textColor)
                .animation(.easeInOut(duration: 0.3), value: rotatingTextIndex)

            Text("Generating \(mode.title)")
                .font(.rethinkSans(11))
                .foregroundColor(theme.secondaryTextColor)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            rotatingTextIndex = 0
            rotationTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
                withAnimation {
                    rotatingTextIndex = (rotatingTextIndex + 1) % rotatingMessages.count
                }
            }
        }
        .onDisappear {
            rotationTimer?.invalidate()
            rotationTimer = nil
        }
    }

    // MARK: - Context Header

    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bookTitle)
                .font(.rethinkSans(14, weight: .semibold))
                .foregroundColor(theme.textColor)
                .lineLimit(1)

            HStack(spacing: 6) {
                if !chapterTitle.isEmpty {
                    Text(chapterTitle)
                        .lineLimit(1)
                }
                Text("·")
                Text("\(progressPercent)%")
            }
            .font(.rethinkSans(11))
            .foregroundColor(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: - Mode Card (Unified)

    private func modeCard(mode: AITextMode) -> some View {
        let isActive = activeMode == mode
        let isProcessing = processingMode == mode
        let isReady = readyModes.contains(mode)

        return Button {
            onSelectMode(mode, nil)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 14, weight: .medium))
                    Text(mode.title)
                        .font(.rethinkSans(14, weight: .medium))
                    Spacer()

                    if isActive {
                        Text("ACTIVE")
                            .font(.rethinkSans(9, weight: .bold))
                            .foregroundColor(theme.textColor.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(theme.textColor.opacity(0.08))
                            )
                    } else if isProcessing {
                        ProgressView()
                            .controlSize(.mini)
                    } else if isReady {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(theme.secondaryTextColor.opacity(0.5))
                    }
                }
                .foregroundColor(theme.textColor)

                if isProcessing {
                    Text("Processing...")
                        .font(.rethinkSans(10))
                        .foregroundColor(theme.secondaryTextColor)
                } else {
                    Text(mode.description)
                        .font(.rethinkSans(10))
                        .foregroundColor(theme.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? theme.textColor.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        theme.secondaryTextColor.opacity(isActive ? 0.5 : 0.4),
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    // MARK: - Easy Read Card (with expand-to-generate)

    private func easyReadCard(mode: AITextMode) -> some View {
        let isActive = activeMode == mode
        let isProcessing = processingMode == mode
        let isReady = readyModes.contains(mode)

        return VStack(spacing: 0) {
            Button {
                if isActive || isReady {
                    onSelectMode(mode, nil)
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedEasyRead.toggle()
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 14, weight: .medium))
                        Text(mode.title)
                            .font(.rethinkSans(14, weight: .medium))
                        Spacer()

                        if isActive {
                            Text("ACTIVE")
                                .font(.rethinkSans(9, weight: .bold))
                                .foregroundColor(theme.textColor.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(theme.textColor.opacity(0.08))
                                )
                        } else if isProcessing {
                            ProgressView()
                                .controlSize(.mini)
                        } else if isReady {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(theme.secondaryTextColor.opacity(0.5))
                        }
                    }
                    .foregroundColor(theme.textColor)

                    Text(mode.description)
                        .font(.rethinkSans(10))
                        .foregroundColor(theme.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)

            if expandedEasyRead && !isProcessing && !isActive {
                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.3)

                Button {
                    expandedEasyRead = false
                    onSelectMode(mode, nil)
                } label: {
                    Text("Generate Easy Read")
                        .font(.rethinkSans(12, weight: .medium))
                        .foregroundColor(theme.textColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.textColor.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? theme.textColor.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    theme.secondaryTextColor.opacity(isActive ? 0.5 : 0.4),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    // MARK: - Quick Summary Card (with scope picker)

    private func quickSummaryCard(mode: AITextMode) -> some View {
        let isActive = activeMode == mode
        let isProcessing = processingMode == mode
        let isReady = readyModes.contains(mode)

        return VStack(spacing: 0) {
            Button {
                if isActive || isReady {
                    onSelectMode(mode, .chapter)
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedQuickSummary.toggle()
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 14, weight: .medium))
                        Text(mode.title)
                            .font(.rethinkSans(14, weight: .medium))
                        Spacer()

                        if isActive {
                            Text("ACTIVE")
                                .font(.rethinkSans(9, weight: .bold))
                                .foregroundColor(theme.textColor.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(theme.textColor.opacity(0.08))
                                )
                        } else if isProcessing {
                            ProgressView()
                                .controlSize(.mini)
                        } else if isReady {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(theme.secondaryTextColor.opacity(0.5))
                        }
                    }
                    .foregroundColor(theme.textColor)

                    if isProcessing {
                        Text("Processing...")
                            .font(.rethinkSans(10))
                            .foregroundColor(theme.secondaryTextColor)
                    } else {
                        Text(mode.description)
                            .font(.rethinkSans(10))
                            .foregroundColor(theme.secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)

            if expandedQuickSummary && !isProcessing && !isActive {
                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.3)

                HStack(spacing: 10) {
                    Button {
                        expandedQuickSummary = false
                        onSelectMode(mode, .chapter)
                    } label: {
                        Text("Generate for This Chapter")
                            .font(.rethinkSans(12, weight: .medium))
                            .foregroundColor(theme.textColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.textColor.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        expandedQuickSummary = false
                        onSelectMode(mode, .entireBook)
                    } label: {
                        Text("Generate for Entire Book")
                            .font(.rethinkSans(12, weight: .medium))
                            .foregroundColor(theme.textColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.textColor.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? theme.textColor.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    theme.secondaryTextColor.opacity(isActive ? 0.5 : 0.4),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    // MARK: - Recap Card

    private var recapCard: some View {
        Button {
            onRecapSession()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("Recap Recent Session")
                        .font(.rethinkSans(14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.secondaryTextColor.opacity(0.5))
                }
                .foregroundColor(theme.textColor)

                Text("Get a recap of what you've recently read, then chat with Curator to go deeper.")
                    .font(.rethinkSans(10))
                    .foregroundColor(theme.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.secondaryTextColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

}
