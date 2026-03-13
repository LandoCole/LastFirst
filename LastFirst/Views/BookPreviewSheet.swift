import SwiftUI

// MARK: - Preview Context

struct BookPreviewContext: Identifiable {
    let id = UUID()
    let items: [LibraryItem]
    let initialIndex: Int
}

// MARK: - Book Preview Sheet

struct BookPreviewSheet: View {
    let items: [LibraryItem]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator

    @State private var currentPage: Int?
    @State private var backgroundColors: [UUID: Color] = [:]
    @State private var textColors: [UUID: Color] = [:]
    @State private var addedToLibrary: Set<UUID> = []
    @Namespace private var previewGlassNamespace

    private var currentItem: LibraryItem? {
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
        .task { extractColors() }
    }

    // MARK: - Sheet Card

    private func sheetCard(item: LibraryItem) -> some View {
        let cardBackground = backgroundColors[item.documentId] ?? Color(hex: "1A1A1A")
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

            // Close / library status / menu buttons
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .nativeGlassButton(shape: .circle)
                .conditionalGlassEffectID("previewClose\(item.id)", in: previewGlassNamespace)

                Spacer()

                // In-library indicator (always checkmark for LibraryItems)
                Button {} label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .nativeGlassButton(shape: .circle)
                .conditionalGlassEffectID("previewLibrary\(item.id)", in: previewGlassNamespace)
                .disabled(true)

                Menu {
                    Button(role: .destructive) {
                        appState.deleteItem(item)
                        if items.count <= 1 {
                            dismiss()
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .nativeGlassButton(shape: .circle)
                .conditionalGlassEffectID("previewMenu\(item.id)", in: previewGlassNamespace)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            // Card content
            previewCard(item: item)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sheetShape.fill(cardBackground))
        .clipShape(sheetShape)
    }

    // MARK: - Preview Card

    private func previewCard(item: LibraryItem) -> some View {
        let itemTextColor = textColors[item.documentId] ?? Color.warmBackground

        return VStack(spacing: 20) {
            Spacer()

            // Cover image
            BookCoverView(
                coverImageData: appState.getCoverImage(for: item.documentId),
                title: item.title,
                iconName: item.coverIconName,
                size: CGSize(width: 220, height: 330),
                cornerRadius: 8,
                ribbonState: item.ribbonState,
                scaledToFit: true
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            // Title & Author
            VStack(spacing: 6) {
                Text(item.title)
                    .font(.hedvigLettersSerif(24))
                    .fontWeight(.bold)
                    .foregroundStyle(itemTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let author = item.author, !author.isEmpty {
                    Text(author)
                        .font(.rethinkSans(16))
                        .foregroundStyle(itemTextColor.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // Info + actions card
            infoCard(item: item, textColor: itemTextColor)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Info Card

    private func infoCard(item: LibraryItem, textColor: Color) -> some View {
        VStack(spacing: 14) {
            // Metadata row
            HStack(spacing: 8) {
                Text(fileTypeLabel(for: item))
                    .font(.rethinkSans(13, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))

                if let wc = item.wordCount {
                    Text("\u{00B7}")
                        .foregroundStyle(textColor.opacity(0.4))
                    Text(wc.formattedWordCount)
                        .font(.rethinkSans(13))
                        .foregroundStyle(textColor.opacity(0.6))
                }

                if item.progress.percentComplete > 0 {
                    Text("\u{00B7}")
                        .foregroundStyle(textColor.opacity(0.4))
                    Text("\(Int(item.progress.percentComplete))% read")
                        .font(.rethinkSans(13))
                        .foregroundStyle(textColor.opacity(0.6))
                }
            }

            // Action buttons — context-aware
            actionButtons(item: item, textColor: textColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(textColor.opacity(0.08))
        )
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButtons(item: LibraryItem, textColor: Color) -> some View {
        let itemBackground = backgroundColors[item.documentId] ?? Color(hex: "1A1A1A")

        switch item.inferredStatus {
        case .wantToRead:
            // Never opened — single "Open" button
            HStack(spacing: 12) {
                primaryButton(label: "Open", textColor: textColor, background: itemBackground) {
                    readerCoordinator.openItem(item, appState: appState)
                    dismiss()
                }

                sourceButton(item: item, textColor: textColor)
            }

        case .reading:
            // In progress — "Resume" primary + "Start from Beginning" secondary
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    primaryButton(label: "Resume", textColor: textColor, background: itemBackground) {
                        readerCoordinator.openItem(item, appState: appState)
                        dismiss()
                    }

                    secondaryButton(label: "Start from Beginning", textColor: textColor) {
                        resetAndOpen(item: item)
                    }
                }

                sourceButtonRow(item: item, textColor: textColor)
            }

        case .completed:
            // Completed — "Read Again" primary + "Resume" secondary
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    primaryButton(label: "Read Again", textColor: textColor, background: itemBackground) {
                        resetAndOpen(item: item)
                    }

                    secondaryButton(label: "Resume", textColor: textColor) {
                        readerCoordinator.openItem(item, appState: appState)
                        dismiss()
                    }
                }

                sourceButtonRow(item: item, textColor: textColor)
            }
        }
    }

    private func primaryButton(label: String, textColor: Color, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.rethinkSans(16, weight: .semibold))
                .foregroundStyle(background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(textColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func secondaryButton(label: String, textColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.rethinkSans(16, weight: .medium))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(textColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func sourceButton(item: LibraryItem, textColor: Color) -> some View {
        if let url = sourceURL(for: item) {
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

    @ViewBuilder
    private func sourceButtonRow(item: LibraryItem, textColor: Color) -> some View {
        if let url = sourceURL(for: item) {
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

    private func sourceURL(for item: LibraryItem) -> URL? {
        switch item.source {
        case .web(let web):
            return web.url
        case .curated(let curated):
            return curated.sourceUrl
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private func resetAndOpen(item: LibraryItem) {
        var resetItem = item
        resetItem.progress = ReadingProgress()
        appState.updateItem(resetItem)
        readerCoordinator.openItem(resetItem, appState: appState)
        dismiss()
    }

    private func extractColors() {
        for item in items {
            if let dominant = appState.getDominantCoverColor(for: item.documentId) {
                let darkened = dominant.darkened(by: 0.25)
                backgroundColors[item.documentId] = Color(darkened)
                textColors[item.documentId] = darkened.brightnessComponent > 0.55
                    ? Color(hex: "1A1A1A")
                    : Color.warmBackground
            }
        }
    }

    private func fileTypeLabel(for item: LibraryItem) -> String {
        switch item.source {
        case .localFile(let local):
            switch local.fileType {
            case .epub: return "EPUB"
            case .pdf: return "PDF"
            }
        case .web:
            return "Article"
        case .curated(let c):
            return (c.fileType ?? "article").uppercased()
        }
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
