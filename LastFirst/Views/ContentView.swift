import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab: NavigationTab = .home
    @State private var showCuratorSheet = false
    @State private var homeScrollToTodayTrigger = false
    @State private var curatorInputText = ""
    @Namespace private var bottomBarNamespace

    var body: some View {
        ZStack {
            // Page content — opacity-switched NavigationStacks
            NavigationStack {
                HomeView(
                    scrollToTodayTrigger: homeScrollToTodayTrigger,
                    onNavigateToCurator: { showCuratorSheet = true }
                )
            }
            .opacity(selectedTab == .home ? 1 : 0)
            .allowsHitTesting(selectedTab == .home)

            NavigationStack {
                LibraryView()
            }
            .opacity(selectedTab == .library ? 1 : 0)
            .allowsHitTesting(selectedTab == .library)

            // MiniReaderBar overlay (above bottom bar)
            if readerCoordinator.presentationState == .minimized {
                VStack {
                    Spacer()
                    MiniReaderBar()
                        .padding(.bottom, 68)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(7)
            }

            // Custom bottom bar
            VStack {
                Spacer()
                bottomBar
            }
            .zIndex(8)
        }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: readerCoordinator.presentationState)
        .fullScreenSheet(isPresented: readerCoordinator.isSheetPresented) {
            if let viewModel = readerCoordinator.viewModel,
               let item = readerCoordinator.activeItem {
                ReadingView(viewModel: viewModel, item: item)
                    .preferredColorScheme(appState.settings.appearanceMode.preferredColorScheme)
            }
        }
        .sheet(isPresented: $showCuratorSheet) {
            curatorSheetContent
        }
    }

    @ViewBuilder
    private var curatorSheetContent: some View {
        if let userId = authVM.currentUser?.id {
            CuratorView(
                inputText: $curatorInputText,
                userId: userId
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        } else {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Sign in to use Curator")
                    .font(.hedvigLettersSerif(24))
                Text("Curator uses your account and reading history to research recommendations.")
                    .font(.rethinkSans(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Sign in or create account") {
                    showCuratorSheet = false
                    authVM.skipAuth = false
                }
                .font(.rethinkSans(16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .foregroundStyle(Color(.systemBackground))
                .clipShape(Capsule())
                .padding(.horizontal, 24)
                Button("Not now") {
                    showCuratorSheet = false
                }
                .font(.rethinkSans(14))
                .foregroundStyle(.secondary)
                Spacer()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        GlassContainer {
            HStack(spacing: 12) {
                // Home button
                Button {
                    if selectedTab == .home {
                        homeScrollToTodayTrigger.toggle()
                    } else {
                        selectedTab = .home
                    }
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selectedTab == .home ? .primary : .secondary)
                        .frame(width: 36, height: 36)
                }
                .nativeGlassButton(shape: .circle)
                .conditionalGlassEffectID("homeTab", in: bottomBarNamespace)

                // Curator input (tappable fake text field)
                Button {
                    showCuratorSheet = true
                } label: {
                    HStack {
                        Text("Ask Curator")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                }
                .nativeGlassButton(shape: .pill)
                .conditionalGlassEffectID("curatorInput", in: bottomBarNamespace)

                // Library button
                Button {
                    selectedTab = .library
                } label: {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selectedTab == .library ? .primary : .secondary)
                        .frame(width: 36, height: 36)
                }
                .nativeGlassButton(shape: .circle)
                .conditionalGlassEffectID("libraryTab", in: bottomBarNamespace)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(ReaderCoordinator())
        .environmentObject(AuthViewModel())
}
