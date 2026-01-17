import Foundation
import SwiftUI

struct AppSettings: Codable {
    var isDarkMode: Bool
    var fontSize: CGFloat
    var softStartPercentage: Double
    var defaultWPM: Int
    var defaultReadingMode: ReadingMode
    var dialStyle: DialStyle
    var autoHideDialDelay: AutoHideDialDelay

    init(
        isDarkMode: Bool = false,
        fontSize: CGFloat = 32,
        softStartPercentage: Double = 0.6,
        defaultWPM: Int = 300,
        defaultReadingMode: ReadingMode = .spritz,
        dialStyle: DialStyle = .radial,
        autoHideDialDelay: AutoHideDialDelay = .off
    ) {
        self.isDarkMode = isDarkMode
        self.fontSize = fontSize
        self.softStartPercentage = softStartPercentage
        self.defaultWPM = defaultWPM
        self.defaultReadingMode = defaultReadingMode
        self.dialStyle = dialStyle
        self.autoHideDialDelay = autoHideDialDelay
    }
}

enum ReadingMode: String, Codable, CaseIterable {
    case spritz
    case stream
    case scan

    var displayName: String {
        switch self {
        case .spritz: return "Spritz"
        case .stream: return "Stream"
        case .scan: return "Scan"
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
