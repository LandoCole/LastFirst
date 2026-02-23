import SwiftUI

struct ModeSelector: View {
    @Binding var selectedMode: ReadingMode

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ReadingMode.allCases, id: \.self) { mode in
                let isSelected = mode == selectedMode

                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedMode = mode
                    }
                }) {
                    VStack(spacing: 4) {
                        Text(mode.displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .primary : .secondary)

                        Circle()
                            .fill(isSelected ? Color.primary : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
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
