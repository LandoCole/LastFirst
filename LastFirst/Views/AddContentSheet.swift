import SwiftUI

enum AddContentAction {
    case importFile
    case addURL
    case newCollection
}

struct AddContentSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAction: (AddContentAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 20)

            VStack(spacing: 0) {
                addRow(
                    icon: "doc.badge.plus",
                    title: "Import Book or PDF",
                    subtitle: "ePub, PDF from Files"
                ) {
                    dismiss()
                    onAction(.importFile)
                }

                Divider()
                    .padding(.leading, 56)

                addRow(
                    icon: "link.badge.plus",
                    title: "Add from URL",
                    subtitle: "Article, webpage, online PDF"
                ) {
                    dismiss()
                    onAction(.addURL)
                }

                Divider()
                    .padding(.leading, 56)

                addRow(
                    icon: "plus.rectangle.on.folder",
                    title: "New Curation",
                    subtitle: "Create a curation playlist"
                ) {
                    dismiss()
                    onAction(.newCollection)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    private func addRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rethinkSans(16, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.rethinkSans(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
