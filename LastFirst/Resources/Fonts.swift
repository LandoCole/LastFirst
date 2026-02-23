import SwiftUI

extension Font {
    private enum CustomFontName {
        // Use PostScript names so SwiftUI finds the embedded fonts reliably
        static let rethinkSans = "RethinkSans-Regular"
        static let hedvigLettersSerif = "HedvigLettersSerif-24ptRegular"
    }

    static func rethinkSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(CustomFontName.rethinkSans, size: size).weight(weight)
    }

    static func hedvigLettersSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(CustomFontName.hedvigLettersSerif, size: size).weight(weight)
    }
}
