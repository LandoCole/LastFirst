import SwiftUI

struct ModeSelector: View {
    @Binding var selectedMode: ReadingMode

    var body: some View {
        HStack(spacing: 16) {
            ForEach(ReadingMode.allCases, id: \.self) { mode in
                let isSelected = mode == selectedMode

                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedMode = mode
                    }
                }) {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                        )
                }
            }
        }
    }

    private func iconName(for mode: ReadingMode) -> String {
        switch mode {
        case .spritz:
            return "bolt.fill"
        case .stream:
            return "text.justify.left"
        case .scan:
            return "eye.fill"
        }
    }
}

#Preview("Mode Selector") {
    VStack {
        ModeSelector(
            selectedMode: .constant(.stream)
        )

        Spacer()
    }
    .padding()
}
