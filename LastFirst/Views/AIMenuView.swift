import SwiftUI

struct AIMenuView: View {
    @ObservedObject var viewModel: AIMenuViewModel
    let readerCoordinator: ReaderCoordinator
    let theme: ResolvedReaderTheme
    var onApplyVariant: ((TextVariant) -> Void)?

    enum ViewState: Equatable {
        case chapterList
        case chapterChat(String) // unitID
        case variantReader(UUID) // variant ID

        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.chapterList, .chapterList): return true
            case (.chapterChat(let a), .chapterChat(let b)): return a == b
            case (.variantReader(let a), .variantReader(let b)): return a == b
            default: return false
            }
        }
    }

    @State private var viewState: ViewState = .chapterList
    @State private var showConcisenessPicker = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(theme.secondaryTextColor.opacity(0.8))

            Text(".sparkle placeholder view")
                .font(.headline)
                .foregroundColor(theme.textColor)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chapter List

    private var chapterListView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.textColor)
                Text("AI Menu")
                    .font(.headline)
                    .foregroundColor(theme.textColor)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if viewModel.chapters.isEmpty {
                Spacer()
                ProgressView()
                    .tint(theme.secondaryTextColor)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.chapters) { chapter in
                            chapterRow(chapter)
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
    }

    private func chapterRow(_ chapter: ChapterInfo) -> some View {
        let variantCount = viewModel.variantsForUnit(chapter.id).count
        return Button(action: {
            viewModel.selectedChapter = chapter
            withAnimation(.easeInOut(duration: 0.2)) {
                viewState = .chapterChat(chapter.id)
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor)
                        .lineLimit(2)

                    Text("\(chapter.wordCount.formatted()) words")
                        .font(.caption)
                        .foregroundColor(theme.secondaryTextColor)
                }

                Spacer()

                if variantCount > 0 {
                    Text("\(variantCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.accentColor))
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chapter Chat

    private func chapterChatView(unitID: String) -> some View {
        let chapterTitle = viewModel.chapters.first(where: { $0.id == unitID })?.title ?? "Chapter"

        return VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewState = .chapterList
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.subheadline)
                    }
                    .foregroundColor(theme.textColor)
                }

                Spacer()

                Text(chapterTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.textColor)
                    .lineLimit(1)

                Spacer()

                // Invisible spacer for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.subheadline)
                }
                .opacity(0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Preset buttons
            presetButtonsRow(unitID: unitID)

            // Message thread
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Existing variants for this chapter
                        let existingVariants = viewModel.variantsForUnit(unitID)
                        if !existingVariants.isEmpty {
                            existingVariantsSection(existingVariants)
                        }

                        // Messages
                        ForEach(viewModel.messages) { message in
                            messageBubble(message, unitID: unitID)
                                .id(message.id)
                        }

                        if viewModel.isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(theme.secondaryTextColor)
                                Text("Processing...")
                                    .font(.caption)
                                    .foregroundColor(theme.secondaryTextColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .id("processing")
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, 60)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Text input for custom requests
            customInputBar(unitID: unitID)
        }
    }

    private func presetButtonsRow(unitID: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                presetButton(title: "Speed Clean", icon: "sparkles") {
                    Task {
                        await viewModel.requestSpeedClean(unitID: unitID)
                    }
                }

                if showConcisenessPicker {
                    ForEach(SummaryConciseness.allCases, id: \.rawValue) { level in
                        presetButton(title: level.displayName, icon: "text.redaction") {
                            showConcisenessPicker = false
                            Task {
                                await viewModel.requestSummary(unitID: unitID, conciseness: level)
                            }
                        }
                    }
                } else {
                    presetButton(title: "Summarize", icon: "text.redaction") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showConcisenessPicker = true
                        }
                    }
                }

                presetButton(title: "Audio", icon: "waveform", disabled: true) {}
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private func presetButton(title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(disabled ? theme.secondaryTextColor.opacity(0.4) : theme.textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(theme.backgroundColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(theme.secondaryTextColor.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled || viewModel.isProcessing)
        .overlay(alignment: .topTrailing) {
            if disabled {
                Text("Soon")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary))
                    .offset(x: 4, y: -4)
            }
        }
    }

    // MARK: - Message Bubbles

    private func messageBubble(_ message: AIMenuMessage, unitID: String) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .font(.subheadline)
                    .foregroundColor(message.role == .user ? .white : theme.textColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user ? Color.accentColor : theme.backgroundColor.opacity(0.8))
                            .overlay(
                                message.role == .assistant ?
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(theme.secondaryTextColor.opacity(0.15), lineWidth: 1) : nil
                            )
                    )

                if let variant = message.variant, variant.status == .ready {
                    HStack(spacing: 8) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewState = .variantReader(variant.id)
                            }
                        }) {
                            Label("Preview", systemImage: "eye")
                                .font(.caption.weight(.medium))
                                .foregroundColor(theme.textColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .strokeBorder(theme.secondaryTextColor.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            applyVariantToReader(variant)
                        }) {
                            Label("Read", systemImage: "book")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let variant = message.variant, variant.status == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2)
                        Text("Failed")
                            .font(.caption2)
                    }
                    .foregroundColor(.red.opacity(0.8))
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Existing Variants

    private func existingVariantsSection(_ variants: [TextVariant]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variants")
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.secondaryTextColor)
                .padding(.horizontal, 24)

            ForEach(variants) { variant in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variant.name)
                            .font(.caption.weight(.medium))
                            .foregroundColor(theme.textColor)

                        Text(variant.kind.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundColor(theme.secondaryTextColor)
                    }

                    Spacer()

                    statusBadge(variant.status)

                    if variant.status == .ready {
                        Button(action: {
                            applyVariantToReader(variant)
                        }) {
                            Text("Read")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        Task {
                            let wasActive = readerCoordinator.activeVariant?.id == variant.id
                            await viewModel.deleteVariant(variant)
                            if wasActive {
                                readerCoordinator.clearVariant()
                            }
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }

            Divider()
                .padding(.horizontal, 24)
                .opacity(0.3)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: TextVariantStatus) -> some View {
        switch status {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .processing:
            ProgressView()
                .scaleEffect(0.6)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        case .queued:
            Image(systemName: "clock")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    // MARK: - Custom Input

    private func customInputBar(unitID: String) -> some View {
        HStack(spacing: 10) {
            TextField("Custom instructions...", text: $viewModel.inputText)
                .font(.subheadline)
                .foregroundColor(theme.textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(theme.backgroundColor.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(theme.secondaryTextColor.opacity(0.2), lineWidth: 1)
                        )
                )

            Button(action: {
                let text = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                viewModel.inputText = ""
                Task {
                    await viewModel.requestCustom(unitID: unitID, instructions: text)
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing
                        ? theme.secondaryTextColor.opacity(0.3)
                        : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(theme.backgroundColor.opacity(0.95))
    }

    // MARK: - Variant Reader

    private func variantReaderView(variantID: UUID) -> some View {
        let variant = viewModel.variants.first(where: { $0.id == variantID })

        return VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    if let unitID = variant?.unitID {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewState = .chapterChat(unitID)
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.subheadline)
                    }
                    .foregroundColor(theme.textColor)
                }

                Spacer()

                Text(variant?.name ?? "Variant")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.textColor)

                Spacer()

                if let variant, variant.status == .ready {
                    Button(action: {
                        applyVariantToReader(variant)
                    }) {
                        Text("Apply")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Apply")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Content
            if let variant {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(variant.chunks.filter({ $0.status == .ready }), id: \.segmentID) { chunk in
                            Text(chunk.transformedText)
                                .font(.system(size: max(14, theme.fontSize - 4), design: .serif))
                                .foregroundColor(theme.textColor)
                                .lineSpacing(4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .padding(.bottom, 60)
                }
            } else {
                Spacer()
                Text("Variant not found")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
                Spacer()
            }
        }
    }

    // MARK: - Apply to Reader

    private func applyVariantToReader(_ variant: TextVariant) {
        guard let packages = viewModel.canonicalPackages else { return }

        Task {
            let modifiedPackages = await TextVariantService.shared.apply(variant: variant, to: packages)
            await MainActor.run {
                readerCoordinator.applyVariant(variant, modifiedPackages: modifiedPackages)
                onApplyVariant?(variant)
            }
        }
    }
}
