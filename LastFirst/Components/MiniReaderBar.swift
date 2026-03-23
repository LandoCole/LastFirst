import SwiftUI

struct MiniReaderBar: View {
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @EnvironmentObject var appState: AppState

    let namespace: Namespace.ID?
    let onExpand: (() -> Void)?
    let onDismiss: (() -> Void)?

    @State private var swipeOffset: CGFloat = 0

    private var viewModel: ReadingViewModel? { readerCoordinator.viewModel }
    private var item: LibraryItem? { readerCoordinator.activeItem }

    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            coverThumbnail
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Title + chapter + time remaining
            VStack(alignment: .leading, spacing: 1) {
                Text(item?.title ?? "")
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)

                if let vm = viewModel {
                    let chapterTitle = currentChapterTitle(vm: vm)
                    if let chapterTitle, !chapterTitle.isEmpty {
                        Text(chapterTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Open reader button
            Button {
                handleExpand()
            } label: {
                Image(systemName: "book.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            // Dismiss button
            Button {
                handleDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            // Progress bar along bottom edge
            if let vm = viewModel {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.primary.opacity(0.3))
                        .frame(width: geo.size.width * vm.progress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 20)
            }
        }
        .glassStyle(shape: .pill)
        .padding(.horizontal, 16)
        .modifier(MiniReaderSurfaceTransition(namespace: namespace))
        .offset(x: swipeOffset)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    swipeOffset = value.translation.width
                }
                .onEnded { value in
                    if abs(value.translation.width) > 120 {
                        // Dismiss via swipe
                        let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                        withAnimation(.easeOut(duration: 0.2)) {
                            swipeOffset = direction * UIScreen.main.bounds.width
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            handleDismiss()
                            swipeOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            swipeOffset = 0
                        }
                    }
                }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleExpand()
        }
    }

    private func handleExpand() {
        if let onExpand {
            onExpand()
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                readerCoordinator.expand()
            }
        }
    }

    private func handleDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            readerCoordinator.dismiss(appState: appState)
        }
    }

    private var coverThumbnail: some View {
        BookCoverView(
            coverImageData: readerCoordinator.coverImageData,
            title: item?.title ?? "",
            iconName: item?.coverIconName ?? "book.closed.fill",
            width: 32,
            cornerRadius: 6,
            aspectRatio: 1.0
        )
    }

    private func currentChapterTitle(vm: ReadingViewModel) -> String? {
        guard !vm.chapters.isEmpty else { return nil }
        return vm.chapters.last(where: { $0.startWordIndex <= vm.currentWordIndex })?.title
    }
}

private struct MiniReaderSurfaceTransition: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "readerSurface", in: namespace)
        } else {
            content
        }
    }
}
