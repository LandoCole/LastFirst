import SwiftUI

// MARK: - Preview Context

struct CurationPreviewContext: Identifiable {
    let id = UUID()
    let items: [CurationItem]
    var initialIndex: Int = 0
}

// MARK: - Curation Preview Sheet

struct CurationPreviewSheet: View {
    let items: [CurationItem]
    var initialIndex: Int = 0
    var userId: UUID?
    var onSave: ((CurationItem) -> Void)?
    var curatorModel: String = "claude"

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @State private var currentPage: Int?
    @State private var savedItemIds: Set<UUID> = []
    @State private var showSummarizationSheet = false
    @State private var summarizationItem: CurationItem?
    @Namespace private var previewGlassNamespace

    private var currentItem: CurationItem? {
        guard let page = currentPage, items.indices.contains(page) else { return nil }
        return items[page]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    sheetCard(item: item)
                        .containerRelativeFrame(.horizontal) { length, _ in length - 16 }
                        .scrollTransition(.animated) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                        }
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentPage)
        .contentMargins(.horizontal, 8)
        .ignoresSafeArea()
        .background(ClearSheetBackground())
        .onAppear { currentPage = initialIndex }
        .sheet(isPresented: $showSummarizationSheet) {
            if let item = summarizationItem {
                SummarizationSheet(
                    text: item.extractedText ?? item.displaySummary ?? "",
                    title: item.displayTitle,
                    sourceUrl: itemSourceURL(for: item),
                    model: curatorModel
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Sheet Card

    private func sheetCard(item: CurationItem) -> some View {
        let cardBackground = coverColor(for: item)
        let textColor = cardBackground.brightnessAdaptedTextColor
        let sheetShape = UnevenRoundedRectangle(
            topLeadingRadius: 32,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 32
        )

        return VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            // Close button
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .nativeGlassButton(shape: .circle)
                .conditionalGlassEffectID("curationClose\(item.id)", in: previewGlassNamespace)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            // Card content (scrollable)
            ScrollView(.vertical, showsIndicators: false) {
                previewContent(item: item, textColor: textColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sheetShape.fill(cardBackground))
        .clipShape(sheetShape)
    }

    // MARK: - Preview Content

    private func previewContent(item: CurationItem, textColor: Color) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)

            // Cover
            coverImage(for: item)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            // Title & Author
            VStack(spacing: 6) {
                Text(item.displayTitle)
                    .font(.hedvigLettersSerif(24))
                    .fontWeight(.bold)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let author = item.displayAuthor, !author.isEmpty {
                    Text(author)
                        .font(.rethinkSans(16))
                        .foregroundStyle(textColor.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)

            // Metadata row
            metadataRow(item: item, textColor: textColor)

            // Summary
            if let summary = item.displaySummary, !summary.isEmpty {
                Text(summary)
                    .font(.rethinkSans(14))
                    .foregroundStyle(textColor.opacity(0.8))
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Agent note
            if let note = item.agentNote, !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    Text(note)
                        .font(.rethinkSans(13))
                        .foregroundStyle(textColor.opacity(0.7))
                        .lineLimit(3)
                }
                .padding(.horizontal, 24)
            }

            // Interaction buttons
            interactionRow(item: item, textColor: textColor)

            // Availability badge
            availabilityBadge(item: item, textColor: textColor)

            // Action buttons + source link
            actionButtons(item: item, textColor: textColor, cardBackground: coverColor(for: item))
                .padding(.horizontal, 8)

            Spacer(minLength: 16)
        }
    }

    // MARK: - Metadata Row

    private func metadataRow(item: CurationItem, textColor: Color) -> some View {
        HStack(spacing: 8) {
            if let fileType = item.displayFileType {
                Text(fileType.uppercased())
                    .font(.rethinkSans(13, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))
            }

            if let minutes = item.displayEstimatedReadMinutes {
                Text("\u{00B7}")
                    .foregroundStyle(textColor.opacity(0.4))
                Text("\(minutes) min read")
                    .font(.rethinkSans(13))
                    .foregroundStyle(textColor.opacity(0.6))
            }

            if let wc = item.displayWordCount {
                Text("\u{00B7}")
                    .foregroundStyle(textColor.opacity(0.4))
                Text(wc.formattedWordCount)
                    .font(.rethinkSans(13))
                    .foregroundStyle(textColor.opacity(0.6))
            }
        }
    }

    // MARK: - Interaction Buttons

    private func interactionRow(item: CurationItem, textColor: Color) -> some View {
        HStack(spacing: 24) {
            interactionButton(icon: "hand.thumbsup", kind: "like", item: item, textColor: textColor)
            interactionButton(icon: "hand.thumbsdown", kind: "dislike", item: item, textColor: textColor)
            interactionButton(icon: "bookmark", kind: "bookmark", item: item, textColor: textColor)
        }
    }

    private func interactionButton(icon: String, kind: String, item: CurationItem, textColor: Color) -> some View {
        Button {
            guard let contentId = item.contentId, let userId else { return }
            Task {
                try? await SupabaseManager.shared.postInteraction(
                    userId: userId,
                    contentId: contentId,
                    kind: kind
                )
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(textColor.opacity(0.6))
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Availability Badge

    @ViewBuilder
    private func availabilityBadge(item: CurationItem, textColor: Color) -> some View {
        if let availability = item.displayAvailability, availability != "full_text" {
            HStack(spacing: 6) {
                Image(systemName: availabilityIcon(availability))
                    .font(.system(size: 11))
                Text(availabilityLabel(availability))
                    .font(.rethinkSans(12, weight: .medium))
            }
            .foregroundStyle(availabilityColor(availability))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(availabilityColor(availability).opacity(0.12))
            .clipShape(Capsule())
        }
    }

    // MARK: - Action Buttons

    private func actionButtons(item: CurationItem, textColor: Color, cardBackground: Color) -> some View {
        let isSaved = savedItemIds.contains(item.id)

        return VStack(spacing: 10) {
            if item.displayAvailability == "external_purchase",
               let url = itemSourceURL(for: item) {
                Link(destination: url) {
                    Text("Open in Store")
                        .font(.rethinkSans(16, weight: .semibold))
                        .foregroundStyle(cardBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(textColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                HStack(spacing: 10) {
                    if hasReadableContent(item) {
                        Button {
                            let libraryItem = saveAndGetItem(item)
                            readerCoordinator.openItem(libraryItem, appState: appState)
                            dismiss()
                        } label: {
                            Text("Read Full Text")
                                .font(.rethinkSans(15, weight: .semibold))
                                .foregroundStyle(cardBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(textColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            summarizationItem = item
                            showSummarizationSheet = true
                        } label: {
                            Text("Summarize")
                                .font(.rethinkSans(15, weight: .semibold))
                                .foregroundStyle(textColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(textColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                Button {
                    saveItem(item)
                } label: {
                    Text(isSaved ? "Saved" : "Save to Library")
                        .font(.rethinkSans(hasReadableContent(item) ? 14 : 16, weight: .semibold))
                        .foregroundStyle(isSaved ? textColor.opacity(0.5) : (hasReadableContent(item) ? textColor : cardBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, hasReadableContent(item) ? 10 : 12)
                        .background(isSaved ? textColor.opacity(0.1) : (hasReadableContent(item) ? Color.clear : textColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSaved)
            }

            // Source link
            if let url = itemSourceURL(for: item) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(url.host ?? "Source")
                            .font(.rethinkSans(16, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(textColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(textColor.opacity(0.08))
        )
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImage(for item: CurationItem) -> some View {
        if let url = item.displayImageUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 220, height: 330)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    fallbackCoverLarge(title: item.displayTitle)
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 220, height: 330)
                }
            }
        } else {
            fallbackCoverLarge(title: item.displayTitle)
        }
    }

    private func fallbackCoverLarge(title: String) -> some View {
        let colors = Color.fallbackCoverPalette.map { Color(hex: $0) }
        let index = abs(title.hashValue) % colors.count
        return RoundedRectangle(cornerRadius: 8)
            .fill(colors[index])
            .frame(width: 220, height: 330)
            .overlay {
                Text(title)
                    .font(.hedvigLettersSerif(18))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(16)
            }
    }

    // MARK: - Helpers

    private func coverColor(for item: CurationItem) -> Color {
        let colors = Color.fallbackCoverPalette.map { Color(hex: $0) }
        let index = abs(item.displayTitle.hashValue) % colors.count
        return colors[index]
    }

    private func itemSourceURL(for item: CurationItem) -> URL? {
        if let urlString = item.externalUrl ?? item.content?.sourceUrl {
            return URL(string: urlString)
        }
        return nil
    }

    private func hasReadableContent(_ item: CurationItem) -> Bool {
        item.extractedText != nil || item.externalUrl != nil || item.content?.sourceUrl != nil
    }

    @discardableResult
    private func saveAndGetItem(_ item: CurationItem) -> LibraryItem {
        let libraryItem = appState.addCuratedItem(item)
        savedItemIds.insert(item.id)
        onSave?(item)
        Task {
            try? await SupabaseManager.shared.markCurationItemSaved(itemId: item.id)
            if let contentId = item.contentId, let userId {
                try? await SupabaseManager.shared.postInteraction(
                    userId: userId,
                    contentId: contentId,
                    kind: "bookmark"
                )
            }
        }
        return libraryItem
    }

    private func saveItem(_ item: CurationItem) {
        savedItemIds.insert(item.id)
        onSave?(item)
    }

    private func availabilityIcon(_ availability: String) -> String {
        switch availability {
        case "downloadable": return "arrow.down.circle"
        case "external_purchase": return "cart"
        case "paywalled": return "lock"
        default: return "doc.text"
        }
    }

    private func availabilityLabel(_ availability: String) -> String {
        switch availability {
        case "downloadable": return "Download Available"
        case "external_purchase": return "Purchase Required"
        case "paywalled": return "Subscription Required"
        default: return "Available"
        }
    }

    private func availabilityColor(_ availability: String) -> Color {
        switch availability {
        case "downloadable": return .blue
        case "external_purchase": return .orange
        case "paywalled": return .red
        default: return .green
        }
    }
}

// MARK: - Color Brightness Helper

private extension Color {
    var brightnessAdaptedTextColor: Color {
        Color.warmBackground
    }
}

// MARK: - Clear Sheet Background

private struct ClearSheetBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            var current = view.superview
            while let sv = current {
                sv.backgroundColor = .clear
                current = sv.superview
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
