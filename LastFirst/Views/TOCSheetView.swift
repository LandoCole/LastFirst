import SwiftUI

struct TOCSheetView: View {
    let tocEntries: [TOCEntry]
    let chapters: [Chapter]
    let currentChapterTitle: String?
    var pageList: [PageListEntry] = []
    var onNavigate: ((Chapter) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                if filteredChapters.isEmpty {
                    emptyState
                } else {
                    chapterList
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter chapters")
        }
    }

    private var filteredChapters: [Chapter] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return chapters
        }
        let query = searchText.lowercased()
        return chapters.filter { $0.title.lowercased().contains(query) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Chapters")
                .font(.title3)
                .fontWeight(.medium)

            Text("This document has no table of contents")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var chapterList: some View {
        List {
            ForEach(filteredChapters) { chapter in
                Button {
                    onNavigate?(chapter)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.title)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fontWeight(chapter.title == currentChapterTitle ? .semibold : .regular)

                        Spacer()

                        if chapter.title == currentChapterTitle {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

}
