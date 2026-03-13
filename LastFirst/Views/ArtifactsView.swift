import SwiftUI

struct ArtifactsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let documentId: UUID
    var initialTab: ArtifactTab? = nil
    var onNavigateToBookmark: ((Annotation) -> Void)? = nil

    @State private var selectedTab: ArtifactTab = .images
    @State private var selectedImage: SavedImage?
    @State private var imageFilter: ImageFilter = .all

    enum ArtifactTab: String, CaseIterable {
        case bookmarks = "Bookmarks"
        case images = "Images & Figures"
        case footnotes = "Footnotes"
    }

    enum ImageFilter: String, CaseIterable {
        case all = "All"
        case unseen = "Unseen"
        case bookmarked = "Bookmarked"
    }

    var images: [SavedImage] {
        appState.getSavedImages(for: documentId)
    }

    var filteredImages: [SavedImage] {
        switch imageFilter {
        case .all:
            return images
        case .unseen:
            return images.filter { !$0.isSeen }
        case .bookmarked:
            return images.filter { $0.isBookmarked }
        }
    }

    var unseenCount: Int {
        images.filter { !$0.isSeen }.count
    }

    var footnotes: [Footnote] {
        appState.getFootnotes(for: documentId)
    }

    var bookmarks: [Annotation] {
        appState.getAnnotations(for: documentId).filter { $0.kind == .bookmark }
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Artifact Type", selection: $selectedTab) {
                    ForEach(ArtifactTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Content based on selected tab
                switch selectedTab {
                case .bookmarks:
                    bookmarksContent
                case .images:
                    imagesContent
                case .footnotes:
                    footnotesContent
                }
            }
            .background(Color.warmBackground)
            .navigationTitle("Artifacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedTab == .images && unseenCount > 0 {
                        Text("\(unseenCount) unseen")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let tab = initialTab {
                    selectedTab = tab
                }
            }
            .sheet(item: $selectedImage) { image in
                ImageDetailView(
                    image: image,
                    documentId: documentId
                )
            }
        }
    }

    // MARK: - Images Content
    @ViewBuilder
    private var imagesContent: some View {
        if images.isEmpty {
            emptyImagesState
        } else {
            VStack(spacing: 0) {
                // Filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ImageFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.rawValue,
                                count: countForFilter(filter),
                                isSelected: imageFilter == filter
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    imageFilter = filter
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }

                // Grid
                if filteredImages.isEmpty {
                    emptyFilterState
                } else {
                    imageGrid
                }
            }
        }
    }

    private func countForFilter(_ filter: ImageFilter) -> Int {
        switch filter {
        case .all: return images.count
        case .unseen: return images.filter { !$0.isSeen }.count
        case .bookmarked: return images.filter { $0.isBookmarked }.count
        }
    }

    private var emptyImagesState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Images Found")
                .font(.title3)
                .fontWeight(.medium)

            Text("Images and figures from the book will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var emptyFilterState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.badge.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            Text("No \(imageFilter.rawValue) Images")
                .font(.title3)
                .fontWeight(.medium)

            Text("Try a different filter")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(filteredImages) { image in
                    ImageGridCell(
                        image: image,
                        onTap: {
                            // Mark as seen when tapped
                            if !image.isSeen {
                                appState.markImageAsSeen(image.id, documentId: documentId)
                            }
                            selectedImage = image
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Bookmarks Content
    @ViewBuilder
    private var bookmarksContent: some View {
        if bookmarks.isEmpty {
            emptyBookmarksState
        } else {
            bookmarksList
        }
    }

    private var emptyBookmarksState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Bookmarks")
                .font(.title3)
                .fontWeight(.medium)

            Text("Bookmarks you create while reading will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var bookmarksList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(bookmarks) { bookmark in
                    BookmarkCard(
                        bookmark: bookmark,
                        onDelete: {
                            appState.removeAnnotation(bookmark)
                        },
                        onNavigate: onNavigateToBookmark != nil ? {
                            onNavigateToBookmark?(bookmark)
                            dismiss()
                        } : nil
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Footnotes Content
    @ViewBuilder
    private var footnotesContent: some View {
        if footnotes.isEmpty {
            emptyFootnotesState
        } else {
            footnotesList
        }
    }
    
    private var emptyFootnotesState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Footnotes Found")
                .font(.title3)
                .fontWeight(.medium)

            Text("Footnotes and annotations from the book will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
    
    private var footnotesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(footnotes) { footnote in
                    FootnoteCard(footnote: footnote)
                }
            }
            .padding()
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.3) : Color.gray.opacity(0.2))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.15))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Image Grid Cell
struct ImageGridCell: View {
    let image: SavedImage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                if let uiImage = UIImage(data: image.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(1, contentMode: .fill)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }

                // Badges
                HStack(spacing: 4) {
                    if !image.isSeen {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                    if image.isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    }
                }
                .padding(6)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Image Detail View
struct ImageDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let image: SavedImage
    let documentId: UUID

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let uiImage = UIImage(data: image.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .padding()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(4/3, contentMode: .fit)
                        .cornerRadius(12)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                        )
                        .padding()
                }

                // Info bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Section \(image.pageIndex + 1)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Found \(image.dateFound.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        appState.toggleImageBookmark(image.id, documentId: documentId)
                    } label: {
                        Image(systemName: image.isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 24))
                            .foregroundColor(image.isBookmarked ? .yellow : .gray)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Image")
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
}

// MARK: - Bookmark Card
struct BookmarkCard: View {
    let bookmark: Annotation
    let onDelete: () -> Void
    var onNavigate: (() -> Void)? = nil
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.orange))

                VStack(alignment: .leading, spacing: 2) {
                    if let title = bookmark.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // Expandable content
            if isExpanded {
                if let excerpt = bookmark.excerpt {
                    Text(excerpt)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                }

                if let note = bookmark.note, !note.isEmpty {
                    Text(note)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.top, 4)
                }

                if let onNavigate {
                    Button {
                        onNavigate()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                            Text("Go to position")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Footnote Card
struct FootnoteCard: View {
    let footnote: Footnote
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with indicator
            HStack {
                Text(footnote.indicator)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.blue))
                
                if let context = footnote.contextText {
                    Text(context)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            // Expandable content
            if isExpanded {
                Text(footnote.content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

#Preview {
    ArtifactsView(documentId: UUID())
        .environmentObject(AppState())
}
