import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker: Bool = false
    @State private var searchText: String = ""

    private var filteredBooks: [Book] {
        if searchText.isEmpty {
            return appState.library
        }
        return appState.library.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.author.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                if appState.library.isEmpty {
                    emptyLibraryView
                } else {
                    libraryContent
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showFilePicker = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search books")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.epub, .pdf, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    // MARK: - Empty State
    private var emptyLibraryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.5))

            VStack(spacing: 8) {
                Text("No Books Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Import an ePub, PDF, or text file to start reading")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showFilePicker = true }) {
                Label("Import Book", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primary)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Library Content
    private var libraryContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredBooks) { book in
                    BookRow(book: book)
                        .contextMenu {
                            Button(role: .destructive) {
                                appState.deleteBook(book)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - File Import
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            // Determine file type
            let fileType: Book.FileType
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "epub":
                fileType = .epub
            case "pdf":
                fileType = .pdf
            case "txt":
                fileType = .txt
            default:
                return
            }

            // Copy file to app's documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)

                // Create book entry
                let book = Book(
                    title: url.deletingPathExtension().lastPathComponent,
                    filePath: destinationURL.path,
                    fileType: fileType
                )

                appState.addBook(book)
            } catch {
                print("Error importing file: \(error)")
            }

        case .failure(let error):
            print("File picker error: \(error)")
        }
    }
}

struct BookRow: View {
    let book: Book
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: selectBook) {
            HStack(spacing: 16) {
                // Cover image or placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))

                    if let coverData = appState.getCoverImage(for: book.id),
                       let uiImage = UIImage(data: coverData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else if let coverData = book.coverImageData,
                              let uiImage = UIImage(data: coverData) {
                        // Fallback to legacy cover data if not migrated yet
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 24))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Text(book.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        // Progress
                        if book.lastReadPosition.percentComplete > 0 {
                            Text("\(Int(book.lastReadPosition.percentComplete))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // File type badge
                        Text(book.fileType.rawValue.uppercased())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Spacer()

                // Last opened indicator
                if let lastOpened = book.lastOpened {
                    VStack(alignment: .trailing) {
                        Text(lastOpened, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)

        Divider()
            .padding(.leading, 96)
    }

    private func selectBook() {
        appState.currentBook = book
        dismiss()
    }
}

// MARK: - UTType Extension
extension UTType {
    static let epub = UTType(filenameExtension: "epub") ?? .data
}

#Preview {
    LibraryView()
        .environmentObject(AppState())
}
