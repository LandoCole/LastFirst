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
    @Namespace private var readerTransitionNamespace
    @State private var readerDragOffset: CGFloat = 0
    @Namespace private var curatorTransitionNamespace
    @State private var curatorDragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Page content — opacity-switched NavigationStacks
            NavigationStack {
                HomeView(
                    scrollToTodayTrigger: homeScrollToTodayTrigger,
                    onNavigateToCurator: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            showCuratorSheet = true
                        }
                    }
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
                    MiniReaderBar(
                        namespace: readerTransitionNamespace,
                        onExpand: expandReader,
                        onDismiss: dismissReader
                    )
                        .padding(.bottom, 68)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(7)
            }

            if readerCoordinator.presentationState == .expanded,
               let viewModel = readerCoordinator.viewModel,
               let item = readerCoordinator.activeItem {
                ZStack(alignment: .top) {
                    ReadingView(viewModel: viewModel, item: item)
                        .preferredColorScheme(appState.settings.appearanceMode.preferredColorScheme)
                        .matchedGeometryEffect(id: "readerSurface", in: readerTransitionNamespace)
                        .ignoresSafeArea()
                        .offset(y: presentedReaderYOffset)
                        .simultaneousGesture(readerDismissGesture)

                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 36, height: 5)
                        .padding(.top, topSafeArea + 6)
                        .offset(y: presentedReaderYOffset)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .zIndex(20)
            }

            // Custom bottom bar
            VStack {
                Spacer()
                bottomBar
            }
            .zIndex(8)

            // Curator overlay (in-ZStack for matchedGeometryEffect morph)
            if showCuratorSheet {
                ZStack(alignment: .top) {
                    curatorSheetContent
                        .matchedGeometryEffect(id: "curatorSurface", in: curatorTransitionNamespace)
                        .ignoresSafeArea()
                        .offset(y: max(0, curatorDragOffset))
                        .simultaneousGesture(curatorDismissGesture)

                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 36, height: 5)
                        .padding(.top, topSafeArea + 6)
                        .offset(y: max(0, curatorDragOffset))
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .zIndex(15)
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: readerCoordinator.presentationState)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showCuratorSheet)
    }

    private var topSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = windowScene.windows.first else {
            return 59
        }

        return window.safeAreaInsets.top
    }

    private var presentedReaderYOffset: CGFloat {
        max(0, readerDragOffset)
    }

    private var readerDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard canStartReaderDismissGesture(value) else {
                    return
                }

                let verticalTranslation = value.translation.height
                let horizontalTranslation = value.translation.width

                guard abs(verticalTranslation) > abs(horizontalTranslation) else {
                    return
                }

                if verticalTranslation > 0 {
                    readerDragOffset = verticalTranslation
                } else {
                    readerDragOffset = verticalTranslation * 0.08
                }
            }
            .onEnded { value in
                guard canStartReaderDismissGesture(value) else {
                    resetReaderDragOffset()
                    return
                }

                let verticalTranslation = value.translation.height
                let horizontalTranslation = value.translation.width

                guard abs(verticalTranslation) > abs(horizontalTranslation) else {
                    resetReaderDragOffset()
                    return
                }

                let predictedVelocity = value.predictedEndTranslation.height - verticalTranslation

                if verticalTranslation > 150 || predictedVelocity > 500 {
                    minimizeReader()
                } else {
                    resetReaderDragOffset()
                }
            }
    }

    private func canStartReaderDismissGesture(_ value: DragGesture.Value) -> Bool {
        value.startLocation.y <= topSafeArea + 80
    }

    private func resetReaderDragOffset() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            readerDragOffset = 0
        }
    }

    private func minimizeReader() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            readerDragOffset = 0
            readerCoordinator.minimize()
        }
    }

    private func expandReader() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            readerCoordinator.expand()
        }
    }

    private func dismissReader() {
        readerDragOffset = 0
        readerCoordinator.dismiss(appState: appState)
    }

    // MARK: - Curator Dismiss Gesture

    private var curatorDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard canStartCuratorDismissGesture(value) else {
                    return
                }

                let verticalTranslation = value.translation.height
                let horizontalTranslation = value.translation.width

                guard abs(verticalTranslation) > abs(horizontalTranslation) else {
                    return
                }

                if verticalTranslation > 0 {
                    curatorDragOffset = verticalTranslation
                } else {
                    curatorDragOffset = verticalTranslation * 0.08
                }
            }
            .onEnded { value in
                guard canStartCuratorDismissGesture(value) else {
                    resetCuratorDragOffset()
                    return
                }

                let verticalTranslation = value.translation.height
                let horizontalTranslation = value.translation.width

                guard abs(verticalTranslation) > abs(horizontalTranslation) else {
                    resetCuratorDragOffset()
                    return
                }

                let predictedVelocity = value.predictedEndTranslation.height - verticalTranslation

                if verticalTranslation > 150 || predictedVelocity > 500 {
                    dismissCurator()
                } else {
                    resetCuratorDragOffset()
                }
            }
    }

    private func canStartCuratorDismissGesture(_ value: DragGesture.Value) -> Bool {
        value.startLocation.y <= topSafeArea + 80
    }

    private func resetCuratorDragOffset() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            curatorDragOffset = 0
        }
    }

    private func dismissCurator() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            curatorDragOffset = 0
            showCuratorSheet = false
        }
    }

    @ViewBuilder
    private var curatorSheetContent: some View {
        if let userId = authVM.currentUser?.id {
            CuratorView(
                inputText: $curatorInputText,
                userId: userId
            )
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
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        showCuratorSheet = true
                    }
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
                .matchedGeometryEffect(id: "curatorSurface", in: curatorTransitionNamespace)
                .conditionalGlassEffectID("curatorInput", in: bottomBarNamespace)
                .opacity(showCuratorSheet ? 0 : 1)

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
            .padding(.horizontal, 24)
            .padding(.bottom, 0)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(ReaderCoordinator())
        .environmentObject(AuthViewModel())
}
