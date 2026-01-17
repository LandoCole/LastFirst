import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let bookId: UUID

    var bookmarks: [Bookmark] {
        appState.getBookmarks(for: bookId)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground)
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
                BookmarkRow(bookmark: bookmark)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.removeBookmark(bookmark)
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
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: goToBookmark) {
            VStack(alignment: .leading, spacing: 8) {
                if let title = bookmark.title {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Text(bookmark.text)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)

                HStack {
                    Text(bookmark.dateCreated, style: .date)
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

    private func goToBookmark() {
        // This would trigger navigation to the bookmark position
        dismiss()
    }
}

#Preview {
    BookmarksView(bookId: UUID())
        .environmentObject(AppState())
}
