import SwiftUI
import UIKit
import CoreGraphics

// MARK: - Dominant Color Extraction

extension UIImage {
    /// Extracts the dominant color from an image using quantized histogram bucketing.
    /// Skips near-white, near-black, and low-saturation gray pixels.
    /// Returns `nil` if no valid color bucket is found.
    func dominantColor() -> UIColor? {
        let size = 40
        guard let cgImage = self.cgImage else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Quantized histogram: 4-bit per channel → 4096 buckets
        var bucketCounts = [Int: Int]()
        var bucketSumR = [Int: Int]()
        var bucketSumG = [Int: Int]()
        var bucketSumB = [Int: Int]()

        let pixelCount = size * size
        for i in 0..<pixelCount {
            let offset = i * 4
            let r = pixelData[offset]
            let g = pixelData[offset + 1]
            let b = pixelData[offset + 2]
            let a = pixelData[offset + 3]
            guard a > 128 else { continue } // skip transparent

            let rf = CGFloat(r) / 255.0
            let gf = CGFloat(g) / 255.0
            let bf = CGFloat(b) / 255.0
            let color = UIColor(red: rf, green: gf, blue: bf, alpha: 1)

            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &br, alpha: &alpha)

            // Skip near-white and near-black
            if br > 0.90 || br < 0.10 { continue }
            // Skip low-saturation grays
            if s < 0.05 && (br < 0.2 || br > 0.8) { continue }

            let bucket = (Int(r) >> 4) << 8 | (Int(g) >> 4) << 4 | (Int(b) >> 4)
            bucketCounts[bucket, default: 0] += 1
            bucketSumR[bucket, default: 0] += Int(r)
            bucketSumG[bucket, default: 0] += Int(g)
            bucketSumB[bucket, default: 0] += Int(b)
        }

        guard let topBucket = bucketCounts.max(by: { $0.value < $1.value }) else {
            return nil
        }

        let count = topBucket.value
        let avgR = CGFloat(bucketSumR[topBucket.key]!) / CGFloat(count) / 255.0
        let avgG = CGFloat(bucketSumG[topBucket.key]!) / CGFloat(count) / 255.0
        let avgB = CGFloat(bucketSumB[topBucket.key]!) / CGFloat(count) / 255.0

        return UIColor(red: avgR, green: avgG, blue: avgB, alpha: 1.0)
    }
}

extension UIColor {
    /// Returns a new UIColor with brightness reduced by the given fraction (0–1).
    func darkened(by fraction: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: b * (1 - fraction), alpha: a)
    }

    /// Returns a new UIColor with brightness increased toward 1.0 by the given fraction (0–1).
    func lightened(by fraction: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s * (1 - fraction * 0.5), brightness: min(b + (1 - b) * fraction, 1.0), alpha: a)
    }

    /// Returns the brightness component (0–1) in HSB color space.
    var brightnessComponent: CGFloat {
        var b: CGFloat = 0
        getHue(nil, saturation: nil, brightness: &b, alpha: nil)
        return b
    }
}

extension Color {
    /// Returns a darkened version of this color by reducing brightness.
    func darkened(by fraction: CGFloat) -> Color {
        Color(UIColor(self).darkened(by: fraction))
    }

    /// Returns a lightened version of this color by increasing brightness.
    func lightened(by fraction: CGFloat) -> Color {
        Color(UIColor(self).lightened(by: fraction))
    }
}

extension Color {
    /// Initialize from a hex integer, e.g. `Color(hex: 0x463F3A)`.
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Initialize from a hex string, e.g. `Color(hex: "463F3A")`.
    init(hex string: String, opacity: Double = 1.0) {
        let cleaned = string.trimmingCharacters(in: .alphanumerics.inverted)
        let value = UInt(cleaned, radix: 16) ?? 0
        self.init(hex: value, opacity: opacity)
    }

    // Shared app color constants
    static let warmBackground = Color(hex: "F4F3EE")
    static let warmForeground = Color(hex: "463F3A")
    static let goldAccent = Color(hex: "956C24")
    static let darkGold = Color(hex: "B8860B")

    static let fallbackCoverPalette: [String] = [
        "a58a43","999661","a8895a","b77c53","ab6c59",
        "81756d","6a8281","538e95","799496","5e8c72"
    ]

    // App theme colors
    static let appBackground = Color("AppBackground")
    static let appForeground = Color("AppForeground")
    static let accentRed = Color("AccentRed")

    // Computed colors based on color scheme
    static func adaptiveGray(_ opacity: Double) -> Color {
        return Color.gray.opacity(opacity)
    }
}

// Custom color scheme support
struct ThemeColors {
    let background: Color
    let foreground: Color
    let secondaryText: Color
    let accentColor: Color
    let dialBackground: Color
    let dialShadow: Color

    static let light = ThemeColors(
        background: Color(UIColor.systemBackground),
        foreground: Color.primary,
        secondaryText: Color.secondary,
        accentColor: Color.red,
        dialBackground: Color(white: 0.95),
        dialShadow: Color.black.opacity(0.1)
    )

    static let dark = ThemeColors(
        background: Color(UIColor.systemBackground),
        foreground: Color.primary,
        secondaryText: Color.secondary,
        accentColor: Color.red,
        dialBackground: Color(white: 0.15),
        dialShadow: Color.black.opacity(0.3)
    )
}

// Environment key for theme
struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemeColors = .light
}

extension EnvironmentValues {
    var theme: ThemeColors {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
