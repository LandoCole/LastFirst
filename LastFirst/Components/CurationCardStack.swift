import SwiftUI

struct CurationCardStack: View {
    let items: [CurationItem]
    @Binding var selectedDetailItem: CurationItem?

    var body: some View {
        TabView {
            ForEach(items) { item in
                curationCard(item)
                    .onTapGesture {
                        selectedDetailItem = item
                    }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
        .frame(height: 140)
    }

    private func curationCard(_ item: CurationItem) -> some View {
        HStack(spacing: 12) {
            BookCoverView(
                coverImageData: nil,
                coverURL: coverURL(for: item),
                title: item.displayTitle,
                iconName: coverIcon(for: item),
                size: CGSize(width: 80, height: 116),
                cornerRadius: 6
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayTitle)
                        .font(.rethinkSans(14, weight: .semibold))
                        .lineLimit(2)

                    if let badge = availabilityBadge(for: item) {
                        Image(systemName: badge.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(badge.color)
                            .padding(3)
                            .background(badge.color.opacity(0.12))
                            .clipShape(Circle())
                    }
                }

                if let author = item.displayAuthor, !author.isEmpty {
                    Text(author)
                        .font(.rethinkSans(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let note = item.agentNote, !note.isEmpty {
                    Text(note)
                        .font(.rethinkSans(11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.warmBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 4)
    }

    private func coverURL(for item: CurationItem) -> URL? {
        if let urlString = item.content?.coverUrl {
            return URL(string: urlString)
        }
        return nil
    }

    private func coverIcon(for item: CurationItem) -> String {
        switch item.content?.fileType ?? item.itemType {
        case "epub": return "book.closed.fill"
        case "pdf": return "doc.fill"
        default: return "newspaper.fill"
        }
    }

    private func availabilityBadge(for item: CurationItem) -> (icon: String, color: Color)? {
        let availability = item.content?.availability ?? (item.itemType == "external_link" || item.itemType == "book" ? "external_purchase" : nil)
        switch availability {
        case "external_purchase": return ("cart", .orange)
        case "paywalled": return ("lock", .red)
        case "downloadable": return ("arrow.down.circle", .blue)
        default: return nil
        }
    }
}
