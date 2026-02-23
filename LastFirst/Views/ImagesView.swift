import SwiftUI

struct ImagesView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let documentId: UUID

    @State private var selectedImageIndex: Int = 0

    var images: [SavedImage] {
        appState.getSavedImages(for: documentId)
    }

    var unseenImages: [SavedImage] {
        images.filter { !$0.isSeen }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                if images.isEmpty {
                    emptyState
                } else {
                    imageGallery
                }
            }
            .navigationTitle("Images & Figures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !unseenImages.isEmpty {
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

    private var emptyState: some View {
        VStack(spacing: 16) {
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
        }
        .padding()
    }

    private var imageGallery: some View {
        TabView(selection: $selectedImageIndex) {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                ImageCard(
                    image: image,
                    onBookmark: {
                        appState.toggleImageBookmark(image.id, documentId: documentId)
                    },
                    onMarkSeen: {
                        appState.markImageAsSeen(image.id, documentId: documentId)
                    }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onChange(of: selectedImageIndex) { _, newIndex in
            // Mark image as seen when viewed
            if newIndex < images.count {
                let image = images[newIndex]
                if !image.isSeen {
                    appState.markImageAsSeen(image.id, documentId: documentId)
                }
            }
        }
    }
}

struct ImageCard: View {
    let image: SavedImage
    let onBookmark: () -> Void
    let onMarkSeen: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Image
            if let uiImage = UIImage(data: image.imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(4/3, contentMode: .fit)
                    .cornerRadius(12)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                    )
            }

            // Info and actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(image.pageIndex + 1)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !image.isSeen {
                        Label("New", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                Spacer()

                // Bookmark button
                Button(action: onBookmark) {
                    Image(systemName: image.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 20))
                        .foregroundColor(image.isBookmarked ? .yellow : .gray)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    ImagesView(documentId: UUID())
        .environmentObject(AppState())
}
