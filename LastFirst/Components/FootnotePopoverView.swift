import SwiftUI

struct FootnotePopoverView: View {
    let indicator: String
    let bodyText: String
    var onJumpToFootnote: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Drag indicator
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                Spacer()
            }
            .padding(.top, 8)

            // Header
            HStack(spacing: 8) {
                Text(indicator)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.blue)
                    )

                Text("Footnote")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            // Body text
            ScrollView(.vertical, showsIndicators: true) {
                Text(bodyText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            // Jump button
            if let onJumpToFootnote {
                Button {
                    onJumpToFootnote()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("Jump to footnote")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
