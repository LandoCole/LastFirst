import SwiftUI

struct CollapsedDial: View {
    @Binding var wpm: Int
    @Binding var isPlaying: Bool
    @Binding var isPushedDown: Bool
    var onAddBookmark: (() -> Void)?
    var onPlayPauseToggle: (() -> Void)?
    var onShowBookmarks: (() -> Void)?
    var onShowImages: (() -> Void)?
    var unseenImageCount: Int
    
    @State private var showBookmarkFeedback: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Bookmarks button
            Button(action: {
                onShowBookmarks?()
            }) {
                Image(systemName: "bookmark")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 60, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Center: Play/Pause | WPM - tappable area
            HStack(spacing: 8) {
                Text(showBookmarkFeedback ? "Bookmarked" : (isPlaying ? "Playing" : "Paused"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(showBookmarkFeedback ? .primary : .secondary)
                
                Text("|")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
                
                Text("\(wpm) WPM")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(height: 50)
            .contentShape(Rectangle())
            .onTapGesture {
                onPlayPauseToggle?()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                // Trigger haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                // Add bookmark
                onAddBookmark?()
                
                // Show feedback text
                showBookmarkFeedback = true
                
                // Dismiss after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showBookmarkFeedback = false
                }
            }
            
            Spacer()
            
            // Images button
            Button(action: {
                onShowImages?()
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                    
                    if unseenImageCount > 0 {
                        Text("\(unseenImageCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.red))
                            .offset(x: 8, y: -8)
                    }
                }
                .frame(width: 60, height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color(UIColor.tertiarySystemBackground).opacity(0.5))
    }
}

#Preview {
    VStack {
        Spacer()
        CollapsedDial(
            wpm: .constant(350),
            isPlaying: .constant(false),
            isPushedDown: .constant(false),
            onAddBookmark: {},
            onPlayPauseToggle: {},
            onShowBookmarks: {},
            onShowImages: {},
            unseenImageCount: 3
        )
    }
    .background(Color(UIColor.systemBackground))
}
