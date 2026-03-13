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
    var onSelectItem: ((CurationItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int?
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

            // Card content
            previewContent(item: item, textColor: textColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sheetShape.fill(cardBackground))
        .clipShape(sheetShape)
    }

    // MARK: - Preview Content

    private func previewContent(item: CurationItem, textColor: Color) -> some View {
        VStack(spacing: 20) {
            Spacer()

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

            Spacer()

            // Info + actions
            infoCard(item: item, textColor: textColor)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImage(for item: CurationItem) -> some View {
        if let urlString = item.content?.coverUrl, let url = URL(string: urlString) {
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

    // MARK: - Info Card

    private func infoCard(item: CurationItem, textColor: Color) -> some View {
        VStack(spacing: 14) {
            // Metadata row
            HStack(spacing: 8) {
                Text(item.itemType.uppercased())
                    .font(.rethinkSans(13, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))

                if let wc = item.content?.wordCount {
                    Text("\u{00B7}")
                        .foregroundStyle(textColor.opacity(0.4))
                    Text(wc.formattedWordCount)
                        .font(.rethinkSans(13))
                        .foregroundStyle(textColor.opacity(0.6))
                }
            }

            // View Details button
            Button {
                onSelectItem?(item)
            } label: {
                Text("View Details")
                    .font(.rethinkSans(16, weight: .semibold))
                    .foregroundStyle(coverColor(for: item))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(textColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Source link
            if let urlString = item.externalUrl ?? item.content?.sourceUrl,
               let url = URL(string: urlString) {
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

    // MARK: - Helpers

    private func coverColor(for item: CurationItem) -> Color {
        let colors = Color.fallbackCoverPalette.map { Color(hex: $0) }
        let index = abs(item.displayTitle.hashValue) % colors.count
        return colors[index]
    }

}

// MARK: - Color Brightness Helper

private extension Color {
    var brightnessAdaptedTextColor: Color {
        // Default to light text for the muted palette colors
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
