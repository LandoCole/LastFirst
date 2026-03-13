import SwiftUI

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension Int {
    /// Formats a word count for display, e.g. 1500 → "1.5k words", 800 → "800 words"
    var formattedWordCount: String {
        if self >= 1000 {
            let k = Double(self) / 1000.0
            return String(format: "%.1fk words", k)
        }
        return "\(self) words"
    }
}
