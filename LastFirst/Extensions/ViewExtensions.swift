import SwiftUI

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func fullScreenSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(EdgeToEdgeFullScreenSheetModifier(isPresented: isPresented, sheetContent: content))
    }
}

private struct EdgeToEdgeFullScreenSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheetContent: () -> SheetContent

    @State private var isPresentedInternally = false
    @State private var isContentVisible = false
    @State private var isDismissing = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if isPresented && !isPresentedInternally {
                    isPresentedInternally = true
                }
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    isDismissing = false
                    isPresentedInternally = true
                } else if isPresentedInternally && !isDismissing {
                    dismissWithAnimation()
                }
            }
            .fullScreenCover(isPresented: $isPresentedInternally, onDismiss: syncDismissState) {
                EdgeToEdgeFullScreenSheetContainer(
                    isContentVisible: $isContentVisible,
                    onDismiss: dismissWithAnimation,
                    content: sheetContent
                )
                .interactiveDismissDisabled()
                .presentationBackground(.clear)
                .transaction { $0.disablesAnimations = true }
                .onAppear {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        isContentVisible = true
                    }
                }
            }
    }

    private func dismissWithAnimation() {
        guard !isDismissing else {
            return
        }

        isDismissing = true
        let animationDuration = 0.3

        withAnimation(.spring(response: animationDuration, dampingFraction: 0.9)) {
            isContentVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            isPresentedInternally = false
            if isPresented {
                isPresented = false
            }
        }
    }

    private func syncDismissState() {
        isContentVisible = false
        isDismissing = false
        if isPresented {
            isPresented = false
        }
    }
}

private struct EdgeToEdgeFullScreenSheetContainer<SheetContent: View>: View {
    @Binding var isContentVisible: Bool
    let onDismiss: () -> Void
    let content: () -> SheetContent

    @State private var dragOffset: CGFloat = 0

    private var topSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = windowScene.windows.first else {
            return 59
        }

        return window.safeAreaInsets.top
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(isContentVisible ? 0.001 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            if isContentVisible {
                ZStack(alignment: .top) {
                    content()

                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 36, height: 5)
                        .padding(.top, topSafeArea + 6)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .offset(y: presentedYOffset)
                .transition(.move(edge: .bottom))
                .simultaneousGesture(dragGesture)
            }
        }
    }

    private var presentedYOffset: CGFloat {
        max(0, dragOffset)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard canStartDismissGesture(value) else {
                    return
                }

                let verticalTranslation = value.translation.height
                let horizontalTranslation = value.translation.width

                guard abs(verticalTranslation) > abs(horizontalTranslation) else {
                    return
                }

                if verticalTranslation > 0 {
                    dragOffset = verticalTranslation
                } else {
                    dragOffset = verticalTranslation * 0.08
                }
            }
            .onEnded { value in
                guard canStartDismissGesture(value) else {
                    resetDragOffset()
                    return
                }

                let verticalTranslation = value.translation.height
                let horizontalTranslation = value.translation.width

                guard abs(verticalTranslation) > abs(horizontalTranslation) else {
                    resetDragOffset()
                    return
                }

                let predictedVelocity = value.predictedEndTranslation.height - verticalTranslation

                if verticalTranslation > 150 || predictedVelocity > 500 {
                    onDismiss()
                } else {
                    resetDragOffset()
                }
            }
    }

    private func canStartDismissGesture(_ value: DragGesture.Value) -> Bool {
        value.startLocation.y <= topSafeArea + 80
    }

    private func resetDragOffset() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = 0
        }
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
