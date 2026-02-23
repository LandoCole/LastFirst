import SwiftUI

struct CatalogCoverView: View {
    let item: CatalogItem
    var size: CGSize = CGSize(width: 116, height: 169)
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(placeholderColor)

            if let url = item.coverURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderContent
                    case .empty:
                        ProgressView()
                            .tint(.white.opacity(0.6))
                    @unknown default:
                        placeholderContent
                    }
                }
            } else {
                placeholderContent
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholderContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.system(size: size.width <= 64 ? 20 : 28))
                .foregroundColor(.white.opacity(0.8))
            Text(item.title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var placeholderColor: Color {
        let colors: [Color] = [
            Color(hex: "3C5A5E"),
            Color(hex: "5E3C4A"),
            Color(hex: "4A5E3C"),
            Color(hex: "3C4A5E"),
            Color(hex: "5E4A3C"),
        ]
        let index = abs(item.title.hashValue) % colors.count
        return colors[index]
    }
}
