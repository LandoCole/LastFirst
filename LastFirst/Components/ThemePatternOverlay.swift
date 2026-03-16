import SwiftUI

struct ThemePatternOverlay: View {
    let pattern: ReaderBackgroundPattern
    let variant: ReaderThemeVariant
    let compact: Bool

    var body: some View {
        switch pattern {
        case .none:
            EmptyView()
        case .dots:
            DotsPatternView(variant: variant, compact: compact)
        case .legal:
            LegalPadPatternView(variant: variant, compact: compact)
        case .blueprint:
            BlueprintPatternView(variant: variant, compact: compact)
        }
    }
}

// MARK: - Legal Pad Pattern

private struct LegalPadPatternView: View {
    let variant: ReaderThemeVariant
    let compact: Bool

    private var lineSpacing: CGFloat { compact ? 14 : 28 }
    private var marginX: CGFloat { compact ? 30 : 60 }

    private var lineColor: Color {
        variant == .light
            ? Color(red: 0.39, green: 0.55, blue: 0.78).opacity(0.25)
            : Color(red: 0.39, green: 0.55, blue: 0.78).opacity(0.15)
    }

    private var marginColor: Color {
        variant == .light
            ? Color(red: 0.78, green: 0.31, blue: 0.31).opacity(0.3)
            : Color(red: 0.78, green: 0.31, blue: 0.31).opacity(0.15)
    }

    var body: some View {
        Canvas { context, size in
            // Horizontal ruled lines
            var y: CGFloat = lineSpacing
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
                y += lineSpacing
            }

            // Red vertical margin line
            let marginPath = Path { p in
                p.move(to: CGPoint(x: marginX, y: 0))
                p.addLine(to: CGPoint(x: marginX, y: size.height))
            }
            context.stroke(marginPath, with: .color(marginColor), lineWidth: 1)
        }
        .mask {
            edgeFadeMask
        }
    }
}

// MARK: - Dots Pattern

private struct DotsPatternView: View {
    let variant: ReaderThemeVariant
    let compact: Bool

    private var dotSpacing: CGFloat { compact ? 4 : 6 }
    private var dotRadius: CGFloat { compact ? 0.35 : 0.5 }

    private var dotColor: Color {
        variant == .light
            ? Color.black.opacity(0.06)
            : Color.white.opacity(0.04)
    }

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let rect = CGRect(
                        x: x - dotRadius,
                        y: y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.fill(Circle().path(in: rect), with: .color(dotColor))
                    x += dotSpacing
                }
                y += dotSpacing
            }
        }
    }
}

// MARK: - Blueprint Pattern

private struct BlueprintPatternView: View {
    let variant: ReaderThemeVariant
    let compact: Bool

    private var gridSpacing: CGFloat { compact ? 20 : 40 }

    private var lineColor: Color {
        variant == .light
            ? Color.white.opacity(0.08)
            : Color(red: 0.22, green: 0.52, blue: 1.0).opacity(0.06)
    }

    var body: some View {
        Canvas { context, size in
            // Vertical grid lines
            var x: CGFloat = gridSpacing
            while x < size.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
                x += gridSpacing
            }

            // Horizontal grid lines
            var y: CGFloat = gridSpacing
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
                y += gridSpacing
            }
        }
        .mask {
            edgeFadeMask
        }
    }
}

// MARK: - Shared Edge Fade Mask

private var edgeFadeMask: some View {
    ZStack {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.85),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.96),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
