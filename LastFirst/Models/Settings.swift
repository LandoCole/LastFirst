import Foundation
import SwiftUI

struct AppSettings: Codable {
    var fontSize: CGFloat
    var appearanceMode: AppearanceMode
    var readerBrightness: Double
    var readerThemeSettings: ReaderThemeSettings
    var softStartPercentage: Double
    var defaultWPM: Int
    var paragraphBreathMs: Int
    var defaultReadingMode: ReadingMode
    var dialStyle: DialStyle
    var autoHideDialDelay: AutoHideDialDelay
    var appAppearanceMode: AppearanceMode

    init(
        fontSize: CGFloat = 32,
        appearanceMode: AppearanceMode = .system,
        readerBrightness: Double = 0.8,
        readerThemeSettings: ReaderThemeSettings = ReaderThemeSettings(),
        softStartPercentage: Double = 0.6,
        defaultWPM: Int = 300,
        paragraphBreathMs: Int = 250,
        defaultReadingMode: ReadingMode = .spritz,
        dialStyle: DialStyle = .radial,
        autoHideDialDelay: AutoHideDialDelay = .off,
        appAppearanceMode: AppearanceMode = .system
    ) {
        self.fontSize = fontSize
        self.appearanceMode = appearanceMode
        self.readerBrightness = readerBrightness
        self.readerThemeSettings = readerThemeSettings
        self.softStartPercentage = softStartPercentage
        self.defaultWPM = defaultWPM
        self.paragraphBreathMs = paragraphBreathMs
        self.defaultReadingMode = defaultReadingMode
        self.dialStyle = dialStyle
        self.autoHideDialDelay = autoHideDialDelay
        self.appAppearanceMode = appAppearanceMode
    }

    enum CodingKeys: String, CodingKey {
        case fontSize
        case appearanceMode
        case readerBrightness
        case readerThemeSettings
        case softStartPercentage
        case defaultWPM
        case paragraphBreathMs
        case defaultReadingMode
        case dialStyle
        case autoHideDialDelay
        case appAppearanceMode
        case isDarkMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyIsDarkMode = try container.decodeIfPresent(Bool.self, forKey: .isDarkMode)

        let fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 32
        let appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)
            ?? (legacyIsDarkMode == true ? .dark : .system)
        let readerBrightness = try container.decodeIfPresent(Double.self, forKey: .readerBrightness) ?? 0.8
        let readerThemeSettings = try container.decodeIfPresent(ReaderThemeSettings.self, forKey: .readerThemeSettings)
            ?? ReaderThemeSettings()
        let softStartPercentage = try container.decodeIfPresent(Double.self, forKey: .softStartPercentage) ?? 0.6
        let defaultWPM = try container.decodeIfPresent(Int.self, forKey: .defaultWPM) ?? 300
        let paragraphBreathMs = try container.decodeIfPresent(Int.self, forKey: .paragraphBreathMs) ?? 250
        let defaultReadingMode = try container.decodeIfPresent(ReadingMode.self, forKey: .defaultReadingMode) ?? .spritz
        let dialStyle = try container.decodeIfPresent(DialStyle.self, forKey: .dialStyle) ?? .radial
        let autoHideDialDelay = try container.decodeIfPresent(AutoHideDialDelay.self, forKey: .autoHideDialDelay) ?? .off
        let appAppearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appAppearanceMode) ?? .system

        self.init(
            fontSize: fontSize,
            appearanceMode: appearanceMode,
            readerBrightness: readerBrightness,
            readerThemeSettings: readerThemeSettings,
            softStartPercentage: softStartPercentage,
            defaultWPM: defaultWPM,
            paragraphBreathMs: paragraphBreathMs,
            defaultReadingMode: defaultReadingMode,
            dialStyle: dialStyle,
            autoHideDialDelay: autoHideDialDelay,
            appAppearanceMode: appAppearanceMode
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(readerBrightness, forKey: .readerBrightness)
        try container.encode(readerThemeSettings, forKey: .readerThemeSettings)
        try container.encode(softStartPercentage, forKey: .softStartPercentage)
        try container.encode(defaultWPM, forKey: .defaultWPM)
        try container.encode(paragraphBreathMs, forKey: .paragraphBreathMs)
        try container.encode(defaultReadingMode, forKey: .defaultReadingMode)
        try container.encode(dialStyle, forKey: .dialStyle)
        try container.encode(autoHideDialDelay, forKey: .autoHideDialDelay)
        try container.encode(appAppearanceMode, forKey: .appAppearanceMode)
    }
}

enum ReadingMode: String, Codable, CaseIterable {
    case spritz
    case stream

    var displayName: String {
        switch self {
        case .spritz: return "Spritz"
        case .stream: return "Stream"
        }
    }
}

enum DialStyle: String, Codable, CaseIterable {
    case radial
    case collapsed
    
    var displayName: String {
        switch self {
        case .radial: return "Radial Dial"
        case .collapsed: return "Collapsed Bar"
        }
    }
}

enum AutoHideDialDelay: String, Codable, CaseIterable {
    case off
    case fiveSeconds
    case fifteenSeconds
    case thirtySeconds
    
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .fiveSeconds: return "5 seconds"
        case .fifteenSeconds: return "15 seconds"
        case .thirtySeconds: return "30 seconds"
        }
    }
    
    var seconds: Double? {
        switch self {
        case .off: return nil
        case .fiveSeconds: return 5
        case .fifteenSeconds: return 15
        case .thirtySeconds: return 30
        }
    }
}
