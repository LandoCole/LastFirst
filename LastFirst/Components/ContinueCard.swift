import SwiftUI

struct ContinueCard: View {
    let item: LibraryItem
    let appState: AppState

    @State private var cardColor: Color = Color(hex: "3C5A5E")
    @State private var textColor: Color = Color(hex: "F4F3EE")

    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            BookCoverView(
                coverImageData: appState.getCoverImage(for: item.documentId),
                title: item.title,
                iconName: item.coverIconName,
                size: CGSize(width: 64, height: 83)
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(.rethinkSans(15, weight: .medium))
                        .foregroundColor(textColor)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "ellipsis")
                        .foregroundColor(textColor.opacity(0.7))
                        .font(.system(size: 14))
                }

                Spacer()

                HStack {
                    Text(item.lastChapterTitle ?? "")
                        .font(.rethinkSans(13))
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(item.progress.percentComplete))% Read")
                        .font(.rethinkSans(13))
                        .foregroundColor(textColor.opacity(0.7))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 105)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardColor)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        )
        .task {
            if let dominant = appState.getDominantCoverColor(for: item.documentId) {
                let darkened = dominant.darkened(by: 0.15)
                cardColor = Color(darkened)
                // Use dark text if the darkened color is still light
                textColor = darkened.brightnessComponent > 0.55
                    ? Color(hex: "1A1A1A")
                    : Color(hex: "F4F3EE")
            }
        }
    }
}
