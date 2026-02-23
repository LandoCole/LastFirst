import SwiftUI
import SwiftData

@main
struct LastFirstApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var readerCoordinator = ReaderCoordinator()
    @StateObject private var authViewModel = AuthViewModel()

    let modelContainer: ModelContainer

    init() {
        let largeTitleFont = UIFont(name: "HedvigLettersSerif-24ptRegular", size: 34)
            ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: largeTitleFont
        ]

        do {
            let schema = Schema([ReadingSessionRecord.self, ReadingStatsCache.self])
            let config = ModelConfiguration("LastFirstMetrics", schema: schema)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isCheckingAuth {
                    SplashView()
                } else if (authViewModel.isAuthenticated && !authViewModel.needsOnboarding) || authViewModel.skipAuth {
                    ContentView()
                } else {
                    AuthView()
                }
            }
            .environmentObject(appState)
            .environmentObject(readerCoordinator)
            .environmentObject(authViewModel)
            .preferredColorScheme(appState.settings.appAppearanceMode.preferredColorScheme)
            .task {
                authViewModel.start()
                setupMetricsSync()
            }
            .onOpenURL { url in
                Task {
                    try? await SupabaseManager.shared.client?.auth.session(from: url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                Task { @MainActor in
                    readerCoordinator.syncService?.stopPeriodicSync()
                    await readerCoordinator.syncService?.syncAll()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { @MainActor in
                    readerCoordinator.syncService?.startPeriodicSync()
                }
            }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func setupMetricsSync() {
        let context = modelContainer.mainContext
        let syncService = ReadingMetricsSyncService(modelContext: context)
        readerCoordinator.syncService = syncService
        syncService.startPeriodicSync()
    }
}
