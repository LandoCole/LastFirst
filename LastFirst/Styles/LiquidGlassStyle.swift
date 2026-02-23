import SwiftUI

// MARK: - Glass Style Constants

/// Central configuration for all Liquid Glass styling in the app.
/// Adjust values here to change glass appearance globally.
enum GlassConstants {
    // MARK: Corner Radii
    static let pillRadius: CGFloat = 100          // Full pill shape
    static let cardRadius: CGFloat = 20           // Cards, panels, containers
    static let buttonRadius: CGFloat = 16         // Small buttons
    static let sheetRadius: CGFloat = 32          // Bottom sheets, modals
    static let badgeRadius: CGFloat = 10          // Small badges

    // MARK: Tint Opacities
    enum Tint {
        static let clear: Double = 0.0
        static let subtle: Double = 0.05
        static let light: Double = 0.1
        static let medium: Double = 0.2
        static let dark: Double = 0.3
        static let heavy: Double = 0.4
    }

    // MARK: Background Opacities (for fill behind content)
    enum Background {
        static let transparent: Double = 0.0
        static let faint: Double = 0.08
        static let light: Double = 0.15
        static let medium: Double = 0.25
        static let strong: Double = 0.4
    }

    // MARK: Icon Circle Backgrounds
    enum IconCircle {
        static let opacity: Double = 0.3
        static let size: CGFloat = 36
    }

    // MARK: Slider Fill
    enum SliderFill {
        static let opacity: Double = 0.85
    }

    // MARK: Dividers
    enum Divider {
        static let opacity: Double = 0.15
        static let thickness: CGFloat = 1
    }

    // MARK: Spacing
    enum Spacing {
        static let pillPadding: CGFloat = 12
        static let cardPadding: CGFloat = 14
        static let itemSpacing: CGFloat = 10
        static let sectionSpacing: CGFloat = 12
    }
}

// MARK: - Glass Tint Preset

/// Predefined tint colors for glass effects
enum GlassTintPreset {
    case clear           // No tint
    case lightNeutral    // Subtle white tint
    case darkNeutral     // Subtle black tint
    case sheetBackground // Darker for modal backgrounds
    case accent          // App accent color tint
    case custom(Color, Double)

    var color: Color {
        switch self {
        case .clear:
            return .clear
        case .lightNeutral:
            return .white
        case .darkNeutral:
            return .black
        case .sheetBackground:
            return .black
        case .accent:
            return .accentColor
        case .custom(let color, _):
            return color
        }
    }

    var opacity: Double {
        switch self {
        case .clear:
            return GlassConstants.Tint.clear
        case .lightNeutral:
            return GlassConstants.Tint.light
        case .darkNeutral:
            return GlassConstants.Tint.medium
        case .sheetBackground:
            return GlassConstants.Tint.dark
        case .accent:
            return GlassConstants.Tint.subtle
        case .custom(_, let opacity):
            return opacity
        }
    }

    var tintColor: Color {
        color.opacity(opacity)
    }
}

// MARK: - Glass Shape Preset

/// Predefined shapes for glass effects
enum GlassShapePreset {
    case pill            // Fully rounded (capsule)
    case card            // Rounded rectangle for cards/panels
    case button          // Smaller rounded rectangle for buttons
    case sheet           // Large radius for modals/sheets
    case circle          // Perfect circle

    var cornerRadius: CGFloat {
        switch self {
        case .pill: return GlassConstants.pillRadius
        case .card: return GlassConstants.cardRadius
        case .button: return GlassConstants.buttonRadius
        case .sheet: return GlassConstants.sheetRadius
        case .circle: return GlassConstants.pillRadius // Will use Circle shape
        }
    }

    func shape() -> AnyShape {
        switch self {
        case .circle:
            AnyShape(Circle())
        default:
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Glass Style Preset

/// Combined presets for common glass UI patterns
enum GlassStylePreset {
    case controlPill           // Brightness/font size sliders
    case horizontalButton      // Mode/Font selector buttons
    case presetCard           // Theme preset grid container
    case expandedPanel        // Expanded customize panel
    case sheetBackground      // Modal/sheet background
    case dialButton           // Speed dial side buttons
    case dialCenter           // Main speed dial circle
    case closeButton          // X close buttons

    var shape: GlassShapePreset {
        switch self {
        case .controlPill: return .pill
        case .horizontalButton: return .pill
        case .presetCard: return .card
        case .expandedPanel: return .card
        case .sheetBackground: return .sheet
        case .dialButton: return .circle
        case .dialCenter: return .circle
        case .closeButton: return .circle
        }
    }

    var tint: GlassTintPreset {
        switch self {
        case .controlPill: return .clear
        case .horizontalButton: return .clear
        case .presetCard: return .lightNeutral
        case .expandedPanel: return .darkNeutral
        case .sheetBackground: return .sheetBackground
        case .dialButton: return .clear
        case .dialCenter: return .clear
        case .closeButton: return .custom(.red, 0.3)
        }
    }
}

// MARK: - View Extensions for Glass Effects

extension View {
    /// Apply a glass effect with a preset style
    @ViewBuilder
    func glassStyle(_ preset: GlassStylePreset, interactive: Bool = false) -> some View {
        glassStyle(shape: preset.shape, tint: preset.tint, interactive: interactive)
    }

    /// Apply a glass effect with custom shape and tint
    @ViewBuilder
    func glassStyle(shape: GlassShapePreset, tint: GlassTintPreset = .clear, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            switch shape {
            case .circle:
                self.glassEffect(
                    interactive ? Glass.regular.tint(tint.tintColor).interactive() : Glass.regular.tint(tint.tintColor),
                    in: Circle()
                )
            default:
                self.glassEffect(
                    interactive ? Glass.regular.tint(tint.tintColor).interactive() : Glass.regular.tint(tint.tintColor),
                    in: RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
                )
            }
        } else {
            // Fallback for iOS < 26
            switch shape {
            case .circle:
                self.background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(tint.tintColor))
                }
            default:
                self.background {
                    RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
                                .fill(tint.tintColor)
                        }
                }
            }
        }
    }

    /// Apply glass effect with shape as background (for proper layering)
    @ViewBuilder
    func glassBackground(_ preset: GlassStylePreset) -> some View {
        glassBackground(shape: preset.shape, tint: preset.tint)
    }

    @ViewBuilder
    func glassBackground(shape: GlassShapePreset, tint: GlassTintPreset = .clear) -> some View {
        if #available(iOS 26.0, *) {
            self.background {
                switch shape {
                case .circle:
                    Circle().fill(Color.clear)
                default:
                    RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
                        .fill(Color.clear)
                }
            }
            .glassStyle(shape: shape, tint: tint)
        } else {
            self.glassStyle(shape: shape, tint: tint)
        }
    }

    /// Conditional glass effect ID for morphing animations (iOS 26+)
    @ViewBuilder
    func conditionalGlassEffectID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Apply native glass button style with shape-aware press highlights (iOS 26+).
    /// Falls back to `.buttonStyle(.plain)` + non-interactive `.glassStyle()` on older iOS.
    @ViewBuilder
    func nativeGlassButton(shape: GlassShapePreset, tint: GlassTintPreset = .clear) -> some View {
        if #available(iOS 26.0, *) {
            switch shape {
            case .circle:
                self.buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            case .pill:
                self.buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            default:
                self.buttonStyle(.glass)
                    .buttonBorderShape(.roundedRectangle(radius: shape.cornerRadius))
            }
        } else {
            self.buttonStyle(.plain)
                .glassStyle(shape: shape, tint: tint)
        }
    }
}

// MARK: - Glass Effect Container Wrapper

/// Wrapper for GlassEffectContainer that falls back gracefully on older iOS
struct GlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = GlassConstants.Spacing.sectionSpacing, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            VStack(spacing: spacing) {
                content()
            }
        }
    }
}

// MARK: - Common Glass UI Components

/// Icon circle used in buttons (Mode, Font, Customize, etc.)
struct GlassIconCircle: View {
    let systemName: String
    var size: CGFloat = GlassConstants.IconCircle.size
    var iconSize: CGFloat = 14
    var fontWeight: Font.Weight = .medium

    var body: some View {
        Circle()
            .fill(Color.white.opacity(GlassConstants.IconCircle.opacity))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: fontWeight))
                    .foregroundStyle(.primary)
            }
    }
}

/// Text icon circle (like "f" for font)
struct GlassTextIconCircle: View {
    let text: String
    var size: CGFloat = GlassConstants.IconCircle.size
    var fontSize: CGFloat = 16
    var fontWeight: Font.Weight = .semibold
    var fontDesign: Font.Design = .default

    var body: some View {
        Circle()
            .fill(Color.white.opacity(GlassConstants.IconCircle.opacity))
            .frame(width: size, height: size)
            .overlay {
                Text(text)
                    .font(.system(size: fontSize, weight: fontWeight, design: fontDesign))
                    .foregroundStyle(.primary)
            }
    }
}

/// Standard two-line label (Title + Subtitle)
struct GlassTwoLineLabel: View {
    let title: String
    let subtitle: String
    var titleSize: CGFloat = 14
    var subtitleSize: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: subtitleSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Close button (X) with glass styling
struct GlassCloseButton: View {
    let action: () -> Void
    var size: CGFloat = 28
    var iconSize: CGFloat = 12

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(GlassConstants.Background.faint)))
        }
    }
}

/// Thin divider for separating sections
struct GlassDivider: View {
    var horizontalPadding: CGFloat = GlassConstants.Spacing.cardPadding

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(GlassConstants.Divider.opacity))
            .frame(height: GlassConstants.Divider.thickness)
            .padding(.horizontal, horizontalPadding)
    }
}
