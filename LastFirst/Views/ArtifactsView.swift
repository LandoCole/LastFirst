import SwiftUI

struct ArtifactsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let bookId: UUID

    @State private var selectedTab: ArtifactTab = .images
    @State private var selectedImageIndex: Int = 0

    enum ArtifactTab: String, CaseIterable {
        case images = "Images & Figures"
        case footnotes = "Footnotes"
    }

    var images: [SavedImage] {
        appState.getSavedImages(for: bookId)
    }

    var unseenImages: [SavedImage] {
        images.filter { !$0.isSeen }
    }
    
    var footnotes: [Footnote] {
        appState.getFootnotes(for: bookId)
    }

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
                case .images:
                    imagesContent
                case .footnotes:
                    footnotesContent
                }
            }
            .background(Color(UIColor.systemBackground))
            .navigationTitle("Artifacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedTab == .images && !unseenImages.isEmpty {
                        Text("\(unseenImages.count) unseen")
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
        }
    }
    
    // MARK: - Images Content
    @ViewBuilder
    private var imagesContent: some View {
        if images.isEmpty {
            emptyImagesState
        } else {
            imageGallery
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

    private var imageGallery: some View {
        TabView(selection: $selectedImageIndex) {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                ImageCard(
                    image: image,
                    onBookmark: {
                        appState.toggleImageBookmark(image.id, bookId: bookId)
                    },
                    onMarkSeen: {
                        appState.markImageAsSeen(image.id, bookId: bookId)
                    }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onChange(of: selectedImageIndex) { _, newIndex in
            if newIndex < images.count {
                let image = images[newIndex]
                if !image.isSeen {
                    appState.markImageAsSeen(image.id, bookId: bookId)
                }
            }
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
    ArtifactsView(bookId: UUID())
        .environmentObject(AppState())
}
