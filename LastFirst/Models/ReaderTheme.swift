import Foundation
import SwiftUI

enum ReaderThemePresetID: String, Codable, CaseIterable, Identifiable {
    case original
    case quiet
    case paper
    case bold
    case calm
    case focus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .quiet: return "Quiet"
        case .paper: return "Paper"
        case .bold: return "Bold"
        case .calm: return "Calm"
        case .focus: return "Focus"
        }
    }
}

enum ReaderThemeVariant: String, Codable {
    case light
    case dark
}

enum ReaderBackgroundPattern: String, Codable {
    case none
    case dots
}

enum ReaderFont: String, Codable, CaseIterable, Identifiable {
    case systemSerif
    case systemSans
    case classicSerif
    case humanist
    case book
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemSerif: return "System Serif"
        case .systemSans: return "System Sans"
        case .classicSerif: return "Classic Serif"
        case .humanist: return "Humanist"
        case .book: return "Book"
        case .mono: return "Mono"
        }
    }

    var shortName: String {
        switch self {
        case .systemSerif: return "Serif"
        case .systemSans: return "Sans"
        case .classicSerif: return "Classic"
        case .humanist: return "Human"
        case .book: return "Book"
        case .mono: return "Mono"
        }
    }

    var swiftUIDesign: Font.Design {
        switch self {
        case .systemSerif: return .serif
        case .systemSans: return .default
        case .classicSerif: return .serif
        case .humanist: return .default
        case .book: return .serif
        case .mono: return .monospaced
        }
    }

    var cssStack: String {
        switch self {
        case .systemSerif:
            return "\"New York\", \"Times New Roman\", serif"
        case .systemSans:
            return "-apple-system, system-ui, \"Helvetica Neue\", sans-serif"
        case .classicSerif:
            return "\"Palatino\", \"Georgia\", serif"
        case .humanist:
            return "\"Avenir\", \"Helvetica Neue\", sans-serif"
        case .book:
            return "\"Baskerville\", \"Times New Roman\", serif"
        case .mono:
            return "\"Menlo\", \"SFMono-Regular\", monospace"
        }
    }
}

struct ReaderThemeDefinition: Codable, Equatable {
    let backgroundColorHex: String
    let textColorHex: String
    let secondaryTextColorHex: String
    let linkColorHex: String
    let pattern: ReaderBackgroundPattern
    let font: ReaderFont
    let bold: Bool
    let lineSpacing: Double
    let letterSpacing: Double
    let wordSpacing: Double
    let margin: Double
    let textJustified: Bool
}

struct ReaderThemeOverride: Codable, Equatable {
    var isEnabled: Bool
    var font: ReaderFont?
    var bold: Bool?
    var lineSpacing: Double?
    var letterSpacing: Double?
    var wordSpacing: Double?
    var margin: Double?
    var textJustified: Bool?
}

struct ReaderThemeSettings: Codable, Equatable {
    var selectedPreset: ReaderThemePresetID
    var overrides: [String: ReaderThemeOverride]

    static let minFontSize: CGFloat = 16
    static let maxFontSize: CGFloat = 48
    static let minMargin: Double = 16
    static let maxMargin: Double = 64
    static let minLineSpacing: Double = 1.1
    static let maxLineSpacing: Double = 2.2
    static let minLetterSpacing: Double = 0
    static let maxLetterSpacing: Double = 0.08
    static let minWordSpacing: Double = 0
    static let maxWordSpacing: Double = 0.18

    init(
        selectedPreset: ReaderThemePresetID = .original,
        overrides: [String: ReaderThemeOverride] = [:]
    ) {
        self.selectedPreset = selectedPreset
        self.overrides = overrides
    }

    func override(for preset: ReaderThemePresetID) -> ReaderThemeOverride? {
        overrides[preset.rawValue]
    }

    mutating func setOverride(_ override: ReaderThemeOverride?, for preset: ReaderThemePresetID) {
        if let override {
            overrides[preset.rawValue] = override
        } else {
            overrides.removeValue(forKey: preset.rawValue)
        }
    }

    mutating func resetOverride(for preset: ReaderThemePresetID) {
        overrides.removeValue(forKey: preset.rawValue)
    }

    static func defaultTheme(for preset: ReaderThemePresetID, variant: ReaderThemeVariant) -> ReaderThemeDefinition {
        switch (preset, variant) {
        case (.original, .light):
            return ReaderThemeDefinition(
                backgroundColorHex: "#FCFBF8",
                textColorHex: "#1C1B1A",
                secondaryTextColorHex: "#5C5855",
                linkColorHex: "#3C3A38",
                pattern: .none,
                font: .systemSerif,
                bold: false,
                lineSpacing: 1.45,
                letterSpacing: 0.0,
                wordSpacing: 0.0,
                margin: 20,
                textJustified: false
            )
        case (.original, .dark):
            return ReaderThemeDefinition(
                backgroundColorHex: "#111112",
                textColorHex: "#EAE6E2",
                secondaryTextColorHex: "#A9A5A0",
                linkColorHex: "#D2CDC7",
                pattern: .none,
                font: .systemSerif,
                bold: false,
                lineSpacing: 1.45,
                letterSpacing: 0.0,
                wordSpacing: 0.0,
                margin: 20,
                textJustified: false
            )
        case (.quiet, .light):
            return ReaderThemeDefinition(
                backgroundColorHex: "#F3F1EE",
                textColorHex: "#3A3836",
                secondaryTextColorHex: "#6A6561",
                linkColorHex: "#4C4946",
                pattern: .none,
                font: .classicSerif,
                bold: false,
                lineSpacing: 1.5,
                letterSpacing: 0.01,
                wordSpacing: 0.02,
                margin: 24,
                textJustified: true
            )
        case (.quiet, .dark):
            return ReaderThemeDefinition(
                backgroundColorHex: "#1E1E1F",
                textColorHex: "#D7D2CB",
                secondaryTextColorHex: "#9D9994",
                linkColorHex: "#B8B2AB",
                pattern: .none,
                font: .classicSerif,
                bold: false,
                lineSpacing: 1.5,
                letterSpacing: 0.01,
                wordSpacing: 0.02,
                margin: 24,
                textJustified: true
            )
        case (.paper, .light):
            return ReaderThemeDefinition(
                backgroundColorHex: "#F9F2E6",
                textColorHex: "#2D2925",
                secondaryTextColorHex: "#665E55",
                linkColorHex: "#4C4540",
                pattern: .dots,
                font: .book,
                bold: false,
                lineSpacing: 1.52,
                letterSpacing: 0.0,
                wordSpacing: 0.01,
                margin: 22,
                textJustified: true
            )
        case (.paper, .dark):
            return ReaderThemeDefinition(
                backgroundColorHex: "#1C1A18",
                textColorHex: "#E9E0D5",
                secondaryTextColorHex: "#B2A89E",
                linkColorHex: "#D5C9BC",
                pattern: .dots,
                font: .book,
                bold: false,
                lineSpacing: 1.52,
                letterSpacing: 0.0,
                wordSpacing: 0.01,
                margin: 22,
                textJustified: true
            )
        case (.bold, .light):
            return ReaderThemeDefinition(
                backgroundColorHex: "#FFFFFF",
                textColorHex: "#111111",
                secondaryTextColorHex: "#5A5A5A",
                linkColorHex: "#111111",
                pattern: .none,
                font: .systemSans,
                bold: true,
                lineSpacing: 1.4,
                letterSpacing: 0.0,
                wordSpacing: 0.0,
                margin: 18,
                textJustified: false
            )
        case (.bold, .dark):
            return ReaderThemeDefinition(
                backgroundColorHex: "#0E0E0F",
                textColorHex: "#F6F4F1",
                secondaryTextColorHex: "#C9C6C2",
                linkColorHex: "#FFFFFF",
                pattern: .none,
                font: .systemSans,
                bold: true,
                lineSpacing: 1.4,
                letterSpacing: 0.0,
                wordSpacing: 0.0,
                margin: 18,
                textJustified: false
            )
        case (.calm, .light):
            return ReaderThemeDefinition(
                backgroundColorHex: "#F6E9D2",
                textColorHex: "#2D2720",
                secondaryTextColorHex: "#6F6354",
                linkColorHex: "#463C33",
                pattern: .none,
                font: .humanist,
                bold: false,
                lineSpacing: 1.6,
                letterSpacing: 0.01,
                wordSpacing: 0.02,
                margin: 26,
                textJustified: true
            )
        case (.calm, .dark):
            return ReaderThemeDefinition(
                backgroundColorHex: "#1A1613",
                textColorHex: "#E7D9C4",
                secondaryTextColorHex: "#BDAF9C",
                linkColorHex: "#D8C7B1",
                pattern: .none,
                font: .humanist,
                bold: false,
                lineSpacing: 1.6,
                letterSpacing: 0.01,
                wordSpacing: 0.02,
                margin: 26,
                textJustified: true
            )
        case (.focus, .light):
            return ReaderThemeDefinition(
                backgroundColorHex: "#FFFDF7",
                textColorHex: "#111111",
                secondaryTextColorHex: "#4B4743",
                linkColorHex: "#2F2C29",
                pattern: .none,
                font: .systemSerif,
                bold: false,
                lineSpacing: 1.35,
                letterSpacing: 0.0,
                wordSpacing: 0.0,
                margin: 16,
                textJustified: false
            )
        case (.focus, .dark):
            return ReaderThemeDefinition(
                backgroundColorHex: "#0F0F10",
                textColorHex: "#F8F5F1",
                secondaryTextColorHex: "#C1BCB6",
                linkColorHex: "#E3DED9",
                pattern: .none,
                font: .systemSerif,
                bold: false,
                lineSpacing: 1.35,
                letterSpacing: 0.0,
                wordSpacing: 0.0,
                margin: 16,
                textJustified: false
            )
        }
    }
}

struct ResolvedReaderTheme: Equatable {
    let preset: ReaderThemePresetID
    let variant: ReaderThemeVariant
    let fontSize: CGFloat
    let definition: ReaderThemeDefinition

    var fontFamily: String {
        definition.font.cssStack
    }

    var fontWeight: String {
        definition.bold ? "600" : "400"
    }

    var cssTextAlign: String {
        definition.textJustified ? "justify" : "left"
    }

    var patternCSS: String {
        switch definition.pattern {
        case .none:
            return "none"
        case .dots:
            return "radial-gradient(circle, rgba(0,0,0,0.06) 0.5px, transparent 0.6px)"
        }
    }

    var patternSizeCSS: String {
        switch definition.pattern {
        case .none:
            return "auto"
        case .dots:
            return "6px 6px"
        }
    }

    var cssString: String {
        """
        :root {
            color-scheme: \(variant == .dark ? "dark" : "light");
        }
        html, body {
            margin: 0;
            padding: 0;
            background-color: \(definition.backgroundColorHex);
            -webkit-text-size-adjust: 100%;
            -webkit-tap-highlight-color: transparent;
            -webkit-font-smoothing: antialiased;
            text-rendering: optimizeLegibility;
        }
        body {
            color: \(definition.textColorHex);
            font-family: \(fontFamily);
            font-size: \(Int(fontSize))px;
            line-height: \(String(format: "%.2f", definition.lineSpacing));
            letter-spacing: \(String(format: "%.3f", definition.letterSpacing))em;
            word-spacing: \(String(format: "%.3f", definition.wordSpacing))em;
            font-weight: \(fontWeight);
            text-align: \(cssTextAlign);
            padding: \(Int(definition.margin))px;
            background-image: \(patternCSS);
            background-size: \(patternSizeCSS);
            touch-action: pan-y;
            -webkit-user-select: none;
            user-select: none;
            -webkit-touch-callout: none;
        }
        p, li {
            margin: 0 0 0.85em 0;
        }
        h1, h2, h3, h4, h5 {
            color: \(definition.textColorHex);
            font-weight: \(fontWeight);
        }
        a {
            color: \(definition.linkColorHex);
            pointer-events: none;
        }
        img, svg, video {
            max-width: 100%;
            height: auto;
            pointer-events: none;
        }
        .lf-highlight {
            background-color: rgba(255, 230, 0, 0.4);
            border-radius: 2px;
        }
        .lf-search-match {
            background-color: rgba(255, 150, 0, 0.4);
            border-radius: 2px;
        }
        .lf-search-active {
            background-color: rgba(255, 150, 0, 0.8);
            outline: 2px solid orange;
            border-radius: 2px;
        }
        """
    }

    var javascriptInjection: String {
        let escapedCSS = cssString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return """
        (function() {
            var styleTag = document.getElementById('lf-reader-theme');
            if (!styleTag) {
                styleTag = document.createElement('style');
                styleTag.id = 'lf-reader-theme';
                document.head.appendChild(styleTag);
            }
            styleTag.innerHTML = "\(escapedCSS)";
        })();
        """
    }
}

enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "Match Device"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var shortName: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    func resolvedVariant(systemScheme: ColorScheme) -> ReaderThemeVariant {
        switch self {
        case .system:
            return systemScheme == .dark ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension ReaderThemeSettings {
    func resolvedTheme(
        appearanceMode: AppearanceMode,
        systemScheme: ColorScheme,
        fontSize: CGFloat
    ) -> ResolvedReaderTheme {
        let variant = appearanceMode.resolvedVariant(systemScheme: systemScheme)
        var base = ReaderThemeSettings.defaultTheme(for: selectedPreset, variant: variant)
        if let override = override(for: selectedPreset), override.isEnabled {
            if let font = override.font {
                base = ReaderThemeDefinition(
                    backgroundColorHex: base.backgroundColorHex,
                    textColorHex: base.textColorHex,
                    secondaryTextColorHex: base.secondaryTextColorHex,
                    linkColorHex: base.linkColorHex,
                    pattern: base.pattern,
                    font: font,
                    bold: override.bold ?? base.bold,
                    lineSpacing: override.lineSpacing ?? base.lineSpacing,
                    letterSpacing: override.letterSpacing ?? base.letterSpacing,
                    wordSpacing: override.wordSpacing ?? base.wordSpacing,
                    margin: override.margin ?? base.margin,
                    textJustified: override.textJustified ?? base.textJustified
                )
            } else {
                base = ReaderThemeDefinition(
                    backgroundColorHex: base.backgroundColorHex,
                    textColorHex: base.textColorHex,
                    secondaryTextColorHex: base.secondaryTextColorHex,
                    linkColorHex: base.linkColorHex,
                    pattern: base.pattern,
                    font: base.font,
                    bold: override.bold ?? base.bold,
                    lineSpacing: override.lineSpacing ?? base.lineSpacing,
                    letterSpacing: override.letterSpacing ?? base.letterSpacing,
                    wordSpacing: override.wordSpacing ?? base.wordSpacing,
                    margin: override.margin ?? base.margin,
                    textJustified: override.textJustified ?? base.textJustified
                )
            }
        }
        return ResolvedReaderTheme(preset: selectedPreset, variant: variant, fontSize: fontSize, definition: base)
    }
}

// MARK: - SwiftUI Helpers for ResolvedReaderTheme

extension ResolvedReaderTheme {
    var textColor: Color { Color(hex: definition.textColorHex) }
    var secondaryTextColor: Color { Color(hex: definition.secondaryTextColorHex) }
    var backgroundColor: Color { Color(hex: definition.backgroundColorHex) }
    var linkColor: Color { Color(hex: definition.linkColorHex) }
    var fontDesign: Font.Design { definition.font.swiftUIDesign }
    var swiftUIFontWeight: Font.Weight { definition.bold ? .semibold : .regular }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch sanitized.count {
        case 6:
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
