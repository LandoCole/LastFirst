import SwiftUI

struct BookCoverView: View {
    let coverImageData: Data?
    var coverURL: URL? = nil
    let title: String
    let iconName: String
    var width: CGFloat = 116
    var cornerRadius: CGFloat = 6
    var ribbonState: RibbonState = .none
    var contentType: CoverContentType = .unknown
    var aspectRatio: CGFloat = 1.5  // height:width — 1.5 = standard 2:3

    @State private var resolvedImage: UIImage?
    @State private var dominantColor: Color?

    private var height: CGFloat { width * aspectRatio }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            coverContent
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            if ribbonState != .none {
                let coverSize = CGSize(width: width, height: height)
                BookCoverRibbon(state: ribbonState, coverSize: coverSize, coverColor: dominantColor)
                    .offset(x: width * 0.075, y: -height * 0.0133)
            }
        }
        .frame(width: width)
        .task(id: coverImageData) {
            await resolveImage()
        }
        .task(id: coverURL) {
            // Only resolve URL if no coverImageData
            if coverImageData == nil {
                await resolveImage()
            }
        }
    }

    // MARK: - Cover Content

    private var coverContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(placeholderColor)

            if let img = resolvedImage {
                imageContent(img)
            } else if coverImageData != nil || coverURL != nil {
                // Loading state
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                placeholderContent
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Image Content

    private func imageContent(_ img: UIImage) -> some View {
        ZStack {
            // Fill image — zooms to fill, clipped
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()

            // Non-EPUB only: dark scrim + title
            if contentType != .epub && width >= 60 {
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height * 0.45)
                }

                titleOverlay
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Title Overlay

    private var titleOverlay: some View {
        VStack {
            Spacer()
            Text(title)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, width * 0.08)
                .padding(.bottom, height * 0.06)
        }
    }

    private var titleFontSize: CGFloat {
        if width <= 60 { return 8 }
        if width <= 100 { return 11 }
        if width <= 160 { return 14 }
        return 18
    }

    // MARK: - Placeholder

    private var placeholderContent: some View {
        VStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: iconSize))
                .foregroundColor(.white.opacity(0.8))
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var placeholderColor: Color {
        let colors = Color.fallbackCoverPalette.map { Color(hex: $0) }
        let index = abs(title.hashValue) % colors.count
        return colors[index]
    }

    private var iconSize: CGFloat {
        if width <= 64 { return 20 }
        if width <= 120 { return 28 }
        return 40
    }

    // MARK: - Image Resolution

    private func resolveImage() async {
        // Try coverImageData first
        if let data = coverImageData, let img = UIImage(data: data) {
            applyImage(img)
            return
        }

        // Try coverURL
        guard let url = coverURL else { return }

        // Check cache
        if let cached = CoverImageCache.shared.image(for: url) {
            applyImage(cached)
            return
        }

        // Download
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let img = UIImage(data: data) else { return }
            CoverImageCache.shared.store(img, for: url)
            applyImage(img)
        } catch {
            // Silently fail — placeholder will show
        }
    }

    private func applyImage(_ img: UIImage) {
        resolvedImage = img
        if let dominant = img.dominantColor() {
            dominantColor = Color(dominant)
        }
    }
}
