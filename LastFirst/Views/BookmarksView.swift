import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let documentId: UUID
    var onNavigateToBookmark: ((Annotation) -> Void)?

    var bookmarks: [Annotation] {
        appState
            .getAnnotations(for: documentId)
            .filter { $0.kind == .bookmark }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.warmBackground
                    .ignoresSafeArea()

                if bookmarks.isEmpty {
                    emptyState
                } else {
                    bookmarksList
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Bookmarks")
                .font(.title3)
                .fontWeight(.medium)

            Text("Tap the + button while reading to save a bookmark")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var bookmarksList: some View {
        List {
            ForEach(bookmarks) { bookmark in
                BookmarkRow(bookmark: bookmark) {
                    onNavigateToBookmark?(bookmark)
                    dismiss()
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        appState.removeAnnotation(bookmark)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct BookmarkRow: View {
    let bookmark: Annotation
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                if let title = bookmark.title {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Text(bookmark.excerpt ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)

                HStack {
                    Text(bookmark.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.gray)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BookmarksView(documentId: UUID())
        .environmentObject(AppState())
}
