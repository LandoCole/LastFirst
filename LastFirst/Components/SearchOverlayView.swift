import SwiftUI

struct SearchSheetView: View {
    @Binding var isPresented: Bool
    var onSearch: ((String) -> Void)?
    var tokenResults: [SearchResult]
    var onResultTapped: ((SearchResult) -> Void)?

    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if tokenResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if tokenResults.isEmpty {
                    ContentUnavailableView(
                        "Search Document",
                        systemImage: "magnifyingglass",
                        description: Text("Type to search through the text")
                    )
                } else {
                    List(tokenResults) { result in
                        Button {
                            onResultTapped?(result)
                            isPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if let chapter = result.chapterTitle {
                                    Text(chapter)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(result.excerpt)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search in document")
        .onChange(of: searchText) { _, newValue in
            onSearch?(newValue)
        }
        .onSubmit(of: .search) {
            onSearch?(searchText)
        }
    }
}

struct SearchResult: Identifiable, Equatable {
    let id = UUID()
    var wordIndex: Int
    var tokenIndex: Int
    var excerpt: String
    var chapterTitle: String?
}
