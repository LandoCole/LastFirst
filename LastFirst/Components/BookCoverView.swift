import SwiftUI

struct BookCoverView: View {
    let coverImageData: Data?
    let title: String
    let iconName: String
    var size: CGSize = CGSize(width: 116, height: 169)
    var cornerRadius: CGFloat = 6
    var ribbonState: RibbonState = .none
    var scaledToFit: Bool = false

    @State private var dominantColor: Color?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Cover content — clipped to rounded rect
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(placeholderColor)

                if let data = coverImageData, let uiImage = UIImage(data: data) {
                    if scaledToFit {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    }
                } else {
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
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // Ribbon — outside clip, free to extend above cover
            if ribbonState != .none {
                BookCoverRibbon(state: ribbonState, coverSize: size, coverColor: dominantColor)
                    .offset(x: size.width * 0.075, y: -size.height * 0.0133)
            }
        }
        .frame(width: size.width, height: size.height)
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

    private var placeholderColor: Color {
        let colors: [Color] = [
            Color(hex: "3C5A5E"),
            Color(hex: "5E3C4A"),
            Color(hex: "4A5E3C"),
            Color(hex: "3C4A5E"),
            Color(hex: "5E4A3C"),
        ]
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
