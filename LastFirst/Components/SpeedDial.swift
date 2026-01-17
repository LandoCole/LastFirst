import SwiftUI

struct SpeedDial: View {
    @Binding var wpm: Int
    @Binding var isPlaying: Bool
    @Binding var isPushedDown: Bool
    var onAddBookmark: (() -> Void)?
    var onPlayPauseToggle: (() -> Void)?

    let minWPM: Int = 100
    let maxWPM: Int = 2000

    // Fun labels for different speeds at major tick marks (every 100 WPM)
    private let speedLabels: [(wpm: Int, label: String)] = [
        (100, "Awake"),
        (200, "Sentient"),
        (300, "Flow"),
        (400, "Cruise"),
        (500, "Page Turner"),
        (600, "Paper Shredder"),
        (700, "Laser Eyes"),
        (800, "Hurricane"),
        (900, "Mind Blender"),
        (1000, "Neural Overclock"),
        (1100, "Over Drive"),
        (1200, "Hypersonic"),
        (1300, "Melting"),
        (1400, "Beyond"),
        (1500, "God Mode"),
        (1600, "Light Speed"),
        (1700, "Ridiculous Speed"),
        (1800, "Ludicrous Speed"),
        (1900, "Plaid"),
        (2000, "There is no Text")
    ]

    private let dialRadius: CGFloat = 280
    
    // Major ticks at every 200 WPM, minor ticks at every 100 WPM for more spacing
    private let majorTickStep: Int = 200
    private let minorTickStep: Int = 100

    // Track drag state
    @State private var dragStartWPM: Int = 0
    @State private var isDragging: Bool = false
    @State private var lastHapticWPM: Int = 0
    @State private var hitLimit: Bool = false
    
    // Bookmark feedback state
    @State private var showBookmarkFeedback: Bool = false

    // Convert WPM to rotation angle (180° range)
    // minWPM = 90° (left side), maxWPM = -90° (right side)
    private var dialRotation: Double {
        let range = Double(maxWPM - minWPM)
        let normalized = Double(wpm - minWPM) / range
        return 90 - (normalized * 180)
    }

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let dialCenterY = geometry.size.height + dialRadius * 0.20

            ZStack {
                // Outer edge tick marks (static, for aesthetics)
                outerTickMarks
                    .frame(width: dialRadius * 2 + 30, height: dialRadius * 2 + 30)
                    .position(x: centerX, y: dialCenterY)
                
                // Fixed background circle with angular gradient (creates dial arm effect pointing up)
                // SwiftUI AngularGradient: 0°=right, 90°=bottom, 180°=left, 270°=top
                // So location 0.75 = 270° = top (12 o'clock)
                Circle()
                    .fill(
                        AngularGradient(
                            stops: [
                                .init(color: Color(UIColor.secondarySystemBackground), location: 0.0),
                                .init(color: Color(UIColor.secondarySystemBackground), location: 0.735),
                                .init(color: Color(UIColor.separator), location: 0.742),
                                .init(color: Color(UIColor.separator), location: 0.758),
                                .init(color: Color(UIColor.secondarySystemBackground), location: 0.765),
                                .init(color: Color(UIColor.secondarySystemBackground), location: 1.0)
                            ],
                            center: .center,

                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        )
                    )
                    .frame(width: dialRadius * 2, height: dialRadius * 2)
                    .position(x: centerX, y: dialCenterY)

                // Main dial body (rotates around center) - 50% opacity so gradient shows through
                dialBody
                    .frame(width: dialRadius * 2, height: dialRadius * 2)
                    .rotationEffect(.degrees(dialRotation), anchor: .center)
                    .position(x: centerX, y: dialCenterY)

                // WPM display above dial
                VStack(spacing: 2) {
                    Text("\(wpm)")
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .foregroundColor(.primary)
                    Text("WPM")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .position(x: centerX, y: dialCenterY - dialRadius - 70)

                // Play/Pause status or Bookmark feedback
                Text(showBookmarkFeedback ? "Bookmarked" : (isPlaying ? "Playing" : "Paused"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(showBookmarkFeedback ? .primary : .secondary)
                    .position(x: centerX, y: dialCenterY - dialRadius - 25)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if !isDragging {
                            onPlayPauseToggle?()
                        }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
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
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWPM = wpm
                            lastHapticWPM = wpm
                            hitLimit = false
                        }

                        // Natural scrolling: moving left increases WPM, right decreases
                        let dragSensitivity: CGFloat = 2.0 // WPM per point dragged
                        let deltaX = value.translation.width
                        let deltaWPM = Int(-deltaX * dragSensitivity)

                        let newWPM = dragStartWPM + deltaWPM
                        // Round to nearest 10
                        let roundedWPM = (newWPM / 10) * 10
                        let clampedWPM = max(minWPM, min(maxWPM, roundedWPM))
                        
                        // Haptic feedback every 100 WPM
                        if abs(clampedWPM - lastHapticWPM) >= 100 {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            lastHapticWPM = clampedWPM
                        }
                        
                        // Double buzz when hitting limits
                        if (roundedWPM < minWPM || roundedWPM > maxWPM) && !hitLimit {
                            hitLimit = true
                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                            generator.impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                generator.impactOccurred()
                            }
                        } else if roundedWPM >= minWPM && roundedWPM <= maxWPM {
                            hitLimit = false
                        }
                        
                        wpm = clampedWPM
                    }
                    .onEnded { _ in
                        isDragging = false
                        hitLimit = false
                    }
            )
        }
    }

    // MARK: - Dial Body
    private var dialBody: some View {
        ZStack {
            // Single circle with adaptive color
            Circle()
                .fill(Color(UIColor.tertiarySystemBackground))
                .opacity(0.5)

            // Generate tick marks at fixed WPM intervals
            // Minor ticks every 50 WPM, major ticks every 100 WPM
            ForEach(Array(stride(from: minWPM, through: maxWPM, by: minorTickStep)), id: \.self) { tickWPM in
                let normalized = Double(tickWPM - minWPM) / Double(maxWPM - minWPM)
                let angle = -90.0 + normalized * 180.0
                let isMajorTick = tickWPM % majorTickStep == 0

                // Tick mark
                Rectangle()
                    .fill(Color.gray.opacity(isMajorTick ? 0.6 : 0.35))
                    .frame(width: isMajorTick ? 1.5 : 0.5, height: isMajorTick ? 14 : 7)
                    .offset(y: -dialRadius + (isMajorTick ? 7 : 3.5))
                    .rotationEffect(.degrees(angle))

                // Label for major ticks - radial pattern reading outward
                if isMajorTick {
                    DialLabel(
                        wpm: tickWPM,
                        label: getLabelForWPM(tickWPM),
                        angle: angle,
                        radius: dialRadius - 45,
                        dialRotation: dialRotation
                    )
                }
            }
        }
    }

    private func getLabelForWPM(_ wpm: Int) -> String? {
        for (labelWPM, label) in speedLabels {
            if wpm == labelWPM {
                return label
            }
        }
        return nil
    }
    
    // MARK: - Outer Edge Tick Marks
    private var outerTickMarks: some View {
        let outerRadius = dialRadius + 15
        let tickCount = 41 // Ticks across 180 degrees
        let centerIndex = tickCount / 2
        
        return ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                // Skip center 3 ticks (center and one on each side)
                if index >= centerIndex - 1 && index <= centerIndex + 1 {
                    EmptyView()
                } else {
                    let angle = -90.0 + (Double(index) / Double(tickCount - 1)) * 180.0
                    let tickHeight: CGFloat = 6
                    let tickWidth: CGFloat = 1
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: tickWidth, height: tickHeight)
                        .offset(y: -outerRadius + tickHeight / 2)
                        .rotationEffect(.degrees(angle))
                }
            }
        }
    }
}

// Label that reads outward in radial pattern from center
struct DialLabel: View {
    let wpm: Int
    let label: String?
    let angle: Double
    let radius: CGFloat
    let dialRotation: Double

    var body: some View {
        VStack(spacing: 1) {
            if let label = label {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray.opacity(0.8))
            }
            Text("\(wpm)")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.gray.opacity(0.7))
        }
        // Counter-rotate to keep text upright: undo both dial rotation and position angle
        .rotationEffect(.degrees(-dialRotation - angle + 90))
        // Position on the dial
        .rotationEffect(.degrees(-90))
        .offset(y: -radius)
        .rotationEffect(.degrees(angle))
    }
}

#Preview {
    ZStack {
        Color(UIColor.systemBackground)
            .ignoresSafeArea()

        VStack {
            Spacer()
            SpeedDial(
                wpm: .constant(350),
                isPlaying: .constant(false),
                isPushedDown: .constant(false),
                onAddBookmark: {},
                onPlayPauseToggle: {}
            )
            .frame(height: 200)
        }
    }
}
