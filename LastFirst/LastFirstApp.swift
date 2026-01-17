import SwiftUI

@main
struct LastFirstApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.isDarkMode ? .dark : .light)
        }
    }
}
