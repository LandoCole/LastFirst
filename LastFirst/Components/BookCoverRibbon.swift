import SwiftUI

// MARK: - Bookmark Shape

struct BookmarkShape: Shape {
    var notchDepth: CGFloat = 0.2

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let topR = min(w * 0.1, 3)          // rounded top corners
        let botR = min(w * 0.08, 2.5)       // rounded notch-junction corners
        let bulge: CGFloat = h * 0.018       // subtle convex top curve
        let notchY = h                       // bottom edge of ribbon
        let notchTipY = notchY - h * notchDepth

        var path = Path()

        // Start below top-left rounded corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topR))

        // Top-left rounded corner
        path.addArc(
            center: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            radius: topR,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Convex top edge (bulging upward)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY - bulge)
        )

        // Top-right rounded corner
        path.addArc(
            center: CGPoint(x: rect.maxX - topR, y: rect.minY + topR),
            radius: topR,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right side down to notch junction
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notchY - botR))

        // Bottom-right rounded corner into notch
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY + notchY),
            tangent2End: CGPoint(x: rect.midX, y: rect.minY + notchTipY),
            radius: botR
        )

        // Right side of V-notch down to tip
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + notchTipY))

        // Left side of V-notch back up
        path.addLine(to: CGPoint(
            x: rect.minX + botR * 0.7,
            y: rect.minY + notchY - botR * 0.15
        ))

        // Bottom-left rounded corner out of notch
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY + notchY),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY + notchY - botR),
            radius: botR
        )

        // Left side back up
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))

        path.closeSubpath()
        return path
    }
}

struct BookCoverRibbon: View {
    let state: RibbonState
    let coverSize: CGSize
    var coverColor: Color?

    private var ribbonWidth: CGFloat { coverSize.width * 0.136 }
    private var ribbonHeight: CGFloat { coverSize.height * 0.141 }

    private let notchDepth: CGFloat = 0.18
    private static let fallbackColor = Color(red: 0.55, green: 0.35, blue: 0.35)

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .added:
            ribbonShape
                .overlay {
                    ribbonGradient
                        .opacity(0.6)
                        .clipShape(BookmarkShape(notchDepth: notchDepth))
                }
                .overlay {
                    BookmarkShape(notchDepth: notchDepth)
                        .stroke(
                            strokeColor,
                            style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])
                        )
                }
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2)
        case .downloaded:
            ribbonShape
                .overlay {
                    ribbonGradient
                        .clipShape(BookmarkShape(notchDepth: notchDepth))
                }
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2)
        }
    }

    private var ribbonShape: some View {
        BookmarkShape(notchDepth: notchDepth)
            .fill(.clear)
            .frame(width: ribbonWidth, height: ribbonHeight)
    }

    // MARK: - Dynamic Color Logic

    private var ribbonBaseColor: Color {
        guard let coverColor else { return Self.fallbackColor }
        let uiColor = UIColor(coverColor)
        let brightness = uiColor.brightnessComponent
        if brightness > 0.5 {
            return Color(uiColor.darkened(by: 0.38))
        } else {
            return Color(uiColor.lightened(by: 0.38))
        }
    }

    private var ribbonGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: ribbonBaseColor.lightened(by: 0.12), location: 0.00),
                Gradient.Stop(color: ribbonBaseColor.darkened(by: 0.08), location: 0.78),
                Gradient.Stop(color: ribbonBaseColor.lightened(by: 0.06), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
    }

    private var strokeColor: Color {
        ribbonBaseColor.lightened(by: 0.25).opacity(0.8)
    }
}
