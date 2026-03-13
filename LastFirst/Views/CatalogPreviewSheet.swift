import SwiftUI

struct CatalogPreviewSheet: View {
    let item: CatalogItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Cover
            CatalogCoverView(
                item: item,
                size: CGSize(width: 160, height: 233),
                cornerRadius: 8
            )
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            .padding(.top, 24)

            // Title & Author
            VStack(spacing: 6) {
                Text(item.title)
                    .font(.hedvigLettersSerif(22))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let author = item.author, !author.isEmpty {
                    Text(author)
                        .font(.rethinkSans(15))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)

            // Metadata
            HStack(spacing: 8) {
                if let fileType = item.fileType?.uppercased() {
                    Text(fileType)
                        .font(.rethinkSans(13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if let wc = item.wordCount {
                    Text("\u{00B7}")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(wc.formattedWordCount)
                        .font(.rethinkSans(13))
                        .foregroundStyle(.secondary)
                }
            }

            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.rethinkSans(14))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

}
