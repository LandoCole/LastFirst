import SwiftUI

struct RuledLinesBackground: View {
    let pattern: ReaderBackgroundPattern
    let variant: ReaderThemeVariant
    let linePitch: CGFloat
    let topOffset: CGFloat
    let marginX: CGFloat?
    let contentHeight: CGFloat
    var topFadeHeight: CGFloat = 0
    var bottomFadeHeight: CGFloat = 0

    var body: some View {
        let canvas: AnyView = switch pattern {
        case .legal:
            AnyView(legalCanvas)
        case .blueprint:
            AnyView(blueprintCanvas)
        case .none, .dots:
            AnyView(EmptyView())
        }

        if topFadeHeight > 0 || bottomFadeHeight > 0 {
            canvas
                .mask {
                    VStack(spacing: 0) {
                        if topFadeHeight > 0 {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: topFadeHeight)
                        }
                        Color.black
                        if bottomFadeHeight > 0 {
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: bottomFadeHeight)
                        }
                    }
                }
        } else {
            canvas
        }
    }

    // MARK: - Legal

    private var legalLineColor: Color {
        variant == .light
            ? Color(red: 0.39, green: 0.55, blue: 0.78).opacity(0.25)
            : Color(red: 0.39, green: 0.55, blue: 0.78).opacity(0.15)
    }

    private var legalMarginColor: Color {
        variant == .light
            ? Color(red: 0.78, green: 0.31, blue: 0.31).opacity(0.3)
            : Color(red: 0.78, green: 0.31, blue: 0.31).opacity(0.15)
    }

    private var legalCanvas: some View {
        Canvas { context, size in
            // Horizontal ruled lines
            guard linePitch > 0 else { return }
            var y = topOffset
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(legalLineColor), lineWidth: 1)
                y += linePitch
            }

            // Red vertical margin line
            if let mx = marginX {
                let marginPath = Path { p in
                    p.move(to: CGPoint(x: mx, y: 0))
                    p.addLine(to: CGPoint(x: mx, y: size.height))
                }
                context.stroke(marginPath, with: .color(legalMarginColor), lineWidth: 1)
            }
        }
        .frame(height: contentHeight)
        .allowsHitTesting(false)
    }

    // MARK: - Blueprint

    private var blueprintLineColor: Color {
        variant == .light
            ? Color.white.opacity(0.08)
            : Color(red: 0.22, green: 0.52, blue: 1.0).opacity(0.06)
    }

    private var blueprintCanvas: some View {
        Canvas { context, size in
            guard linePitch > 0 else { return }

            // Horizontal grid lines aligned to text
            var y = topOffset
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(blueprintLineColor), lineWidth: 0.5)
                y += linePitch
            }

            // Vertical grid lines at linePitch intervals
            var x = linePitch
            while x < size.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(blueprintLineColor), lineWidth: 0.5)
                x += linePitch
            }
        }
        .frame(height: contentHeight)
        .allowsHitTesting(false)
    }
}
