import SwiftUI

struct BookCoverView: View {
    let coverImageData: Data?
    var coverURL: URL? = nil    // For curated/network content
    let title: String
    let iconName: String
    var size: CGSize = CGSize(width: 116, height: 169)
    var cornerRadius: CGFloat = 6
    var ribbonState: RibbonState = .none
    var flexibleAspectRatio: Bool = false

    @State private var dominantColor: Color?

    private var contentMode: ContentMode {
        flexibleAspectRatio ? .fit : .fill
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Cover content — clipped to rounded rect
            coverContent
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // Ribbon — outside clip, free to extend above cover
            if ribbonState != .none {
                BookCoverRibbon(state: ribbonState, coverSize: size, coverColor: dominantColor)
                    .offset(x: size.width * 0.075, y: -size.height * 0.0133)
            }
        }
        .frame(width: size.width, height: flexibleAspectRatio ? nil : size.height)
        .task(id: coverImageData) {
            guard ribbonState != .none,
                  let data = coverImageData,
                  let img = UIImage(data: data),
                  let dominant = img.dominantColor() else {
                dominantColor = nil
                return
            }
            dominantColor = Color(dominant)
        }
    }

    @ViewBuilder
    private var coverContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(placeholderColor)

            if let data = coverImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholderContent
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.6)
                    @unknown default:
                        placeholderContent
                    }
                }
            } else {
                placeholderContent
            }
        }
        .frame(
            width: size.width,
            height: flexibleAspectRatio ? nil : size.height
        )
        .frame(
            minHeight: flexibleAspectRatio ? size.height * 0.85 : nil,
            maxHeight: flexibleAspectRatio ? size.height * 1.15 : nil
        )
    }

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
        if size.width <= 64 {
            return 20
        } else if size.width <= 120 {
            return 28
        } else {
            return 40
        }
    }
}
