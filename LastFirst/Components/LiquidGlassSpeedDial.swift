//
//  LiquidGlassSpeedDial.swift
//  LastFirst
//
//  Speed dial for Spritz mode with rotating tick marks
//  and side buttons for bookmarks and menu.
//  Features true circular/rotational gesture tracking.
//

import SwiftUI

struct LiquidGlassSpeedDial: View {
    @Binding var wpm: Int
    @Binding var isPlaying: Bool
    var controlColor: Color = .secondary

    var onPlayPauseToggle: (() -> Void)?
    var onRewind: (() -> Void)?
    var onForwardSentence: (() -> Void)?
    var onAddBookmark: (() -> Void)?
    var onHoldRewind: (() -> Void)?
    var onHoldForward: (() -> Void)?
    var onHoldRelease: (() -> Void)?

    let minWPM: Int = 100
    let maxWPM: Int = 2000

    // Speed labels for different WPM ranges
    private let speedLabels: [(range: ClosedRange<Int>, label: String)] = [
        (100...149, "Awakening"),
        (150...249, "Sentient"),
        (250...349, "Flowing"),
        (350...449, "Blazing"),
        (450...549, "Cruising"),
        (550...649, "Shredding"),
        (650...749, "Laser"),
        (750...849, "Hurricane"),
        (850...949, "Blending"),
        (950...1049, "Overdrive"),
        (1050...1149, "Hypersonic"),
        (1150...1249, "Melting"),
        (1250...1349, "Beyond"),
        (1350...1449, "God Mode"),
        (1450...1549, "Lightspeed"),
        (1550...1649, "Ridiculous"),
        (1650...1749, "Ludicrous"),
        (1750...1849, "Plaid"),
        (1850...2000, "No Text")
    ]

    // Dial dimensions
    private let dialRadius: CGFloat = 90
    private let glassRadius: CGFloat = 92
    private let sideButtonRadius: CGFloat = 22

    // Circular drag state
    @State private var isDragging: Bool = false
    @State private var dragStartWPM: Int = 0
    @State private var rotaryTracker = RotaryDialTracker(center: .zero)
    @State private var lastHapticWPM: Int = 0
    @State private var hitLimit: Bool = false

    // Visual rotation state for tick marks
    @State private var tickRotation: Double = 0

    // Bookmark feedback
    @State private var showBookmarkFeedback: Bool = false

    // WPM override for showing WPM number while paused and dragging
    @State private var showWPMOverride: Bool = false
    @State private var wpmRevertWorkItem: DispatchWorkItem? = nil

    private var showWPMNumber: Bool {
        isPlaying || showWPMOverride
    }

    private var currentSpeedLabel: String {
        for (range, label) in speedLabels {
            if range.contains(wpm) {
                return label
            }
        }
        return "Flow"
    }

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2

            dialLayout(centerX: centerX, centerY: centerY)
        }
        .frame(height: (glassRadius + 16) * 2)
    }

    @ViewBuilder
    private func dialLayout(centerX: CGFloat, centerY: CGFloat) -> some View {
        let buttonRadius = glassRadius + sideButtonRadius + 24

        ZStack {
            // Left side - Rewind to sentence start (hold to stream backward)
            rewindButton
                .offset(x: -buttonRadius)
                .position(x: centerX, y: centerY)

            // Right side - Forward to next sentence end (hold to stream forward)
            forwardButton
                .offset(x: buttonRadius)
                .position(x: centerX, y: centerY)

            // Dial Assembly
            dialAssembly
                .position(x: centerX, y: centerY)
        }
    }

    // MARK: - Dial Assembly

    private var dialAssembly: some View {
        dialContent
        .contentShape(Circle())
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
                    triggerBookmarkFeedback()
                    onAddBookmark?()
                }
        )
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in

                    handleCircularDrag(value)
                    if !isPlaying && !showWPMOverride {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showWPMOverride = true
                        }
                    }
                    wpmRevertWorkItem?.cancel()
                }
                .onEnded { _ in
                    isDragging = false
                    hitLimit = false
                    rotaryTracker.reset()
                    scheduleWPMRevert()
                }
        )
    }

    // MARK: - Dial Content (no fill, no glass)

    private var dialContent: some View {
        ZStack {
            backgroundDialWithTicks
            dialTextContent
        }
        .frame(width: glassRadius * 2, height: glassRadius * 2)
    }

    // MARK: - Background Dial with Tick Marks

    private var backgroundDialWithTicks: some View {
        tickMarks
            .rotationEffect(.degrees(tickRotation))
            .opacity(0.77)
    }

    private var tickMarks: some View {
        let tickCount = 60
        return ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let angle = Double(index) / Double(tickCount) * 360.0
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 1.5, height: 6)
                    .offset(y: -dialRadius + 8)
                    .rotationEffect(.degrees(angle))
            }
        }
    }

    // MARK: - Dial Text Content

    private var dialTextContent: some View {
        VStack(spacing: 2) {
            Text(currentSpeedLabel)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(.secondary)
                .opacity(0.77)

            ZStack {
                Text("\(wpm)")
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundColor(controlColor)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: wpm)
                    .opacity(showWPMNumber ? 1 : 0)
                    .scaleEffect(showWPMNumber ? 1 : 0.85)

                Image(systemName: "play.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(controlColor)
                    .opacity(showWPMNumber ? 0 : 1)
                    .scaleEffect(showWPMNumber ? 0.85 : 1)
            }
            .frame(height: 52)
            .animation(.easeInOut(duration: 0.35), value: showWPMNumber)

            Text("WPM")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundColor(.secondary)
                .opacity(0.77)
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                wpmRevertWorkItem?.cancel()
                showWPMOverride = false
            } else {
                // Pausing: immediately show play icon
                wpmRevertWorkItem?.cancel()
                showWPMOverride = false
            }
        }
    }

    // MARK: - Rewind Button (tap = sentence skip, hold = stream backward)

    @State private var isHoldingRewind: Bool = false
    @State private var showRewindFlash: Bool = false

    private var rewindButton: some View {
        ZStack {
            Circle()
                .fill(controlColor.opacity(showRewindFlash || isHoldingRewind ? 0.15 : 0))
                .frame(width: sideButtonRadius * 2, height: sideButtonRadius * 2)

            BackArrowShape()
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 22, height: 24)
        }
        .foregroundColor(controlColor)
        .frame(width: sideButtonRadius * 2, height: sideButtonRadius * 2)
        .scaleEffect(isHoldingRewind ? 0.8 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isHoldingRewind)
        .animation(.easeOut(duration: 0.15), value: showRewindFlash)
        .onTapGesture {
            showRewindFlash = true
            onRewind?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showRewindFlash = false
            }
        }
        .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
            isHoldingRewind = pressing
            if pressing {
                onHoldRewind?()
            } else {
                onHoldRelease?()
            }
        }, perform: {})
    }

    // MARK: - Forward Button (tap = sentence skip, hold = stream forward)

    @State private var isHoldingForward: Bool = false
    @State private var showForwardFlash: Bool = false

    private var forwardButton: some View {
        ZStack {
            Circle()
                .fill(controlColor.opacity(showForwardFlash || isHoldingForward ? 0.15 : 0))
                .frame(width: sideButtonRadius * 2, height: sideButtonRadius * 2)

            ForwardArrowShape()
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 22, height: 24)
        }
        .foregroundColor(controlColor)
        .frame(width: sideButtonRadius * 2, height: sideButtonRadius * 2)
        .scaleEffect(isHoldingForward ? 0.8 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isHoldingForward)
        .animation(.easeOut(duration: 0.15), value: showForwardFlash)
        .onTapGesture {
            showForwardFlash = true
            onForwardSentence?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showForwardFlash = false
            }
        }
        .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
            isHoldingForward = pressing
            if pressing {
                onHoldForward?()
            } else {
                onHoldRelease?()
            }
        }, perform: {})
    }

    // MARK: - Circular Drag Handling

    private func handleCircularDrag(_ value: DragGesture.Value) {
        let localCenter = CGPoint(x: glassRadius, y: glassRadius)

        if !isDragging {
            isDragging = true
            dragStartWPM = wpm
            lastHapticWPM = wpm
            hitLimit = false
            rotaryTracker = RotaryDialTracker(center: localCenter)
            rotaryTracker.track(point: value.location)
            return
        }

        let delta = rotaryTracker.track(point: value.location)
        tickRotation += delta

        let wpmPerRevolution: Double = 200.0
        let wpmDelta = rotaryTracker.totalRotation / 360.0 * wpmPerRevolution

        let rawNewWPM = dragStartWPM + Int(wpmDelta)
        let roundedWPM = ((rawNewWPM + 2) / 5) * 5
        let clampedWPM = max(minWPM, min(maxWPM, roundedWPM))

        if abs(clampedWPM - lastHapticWPM) >= 50 {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            lastHapticWPM = clampedWPM
        }

        if (rawNewWPM < minWPM || rawNewWPM > maxWPM) && !hitLimit {
            hitLimit = true
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                generator.impactOccurred()
            }
        } else if rawNewWPM >= minWPM && rawNewWPM <= maxWPM {
            hitLimit = false
        }

        wpm = clampedWPM
    }

    // MARK: - WPM Revert Timer

    private func scheduleWPMRevert() {
        wpmRevertWorkItem?.cancel()
        guard !isPlaying else { return }
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) {
                showWPMOverride = false
            }
        }
        wpmRevertWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    // MARK: - Bookmark Feedback

    private func triggerBookmarkFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        showBookmarkFeedback = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showBookmarkFeedback = false
        }
    }
}

// MARK: - Back Arrow Shape (double chevron pointing left)

private struct BackArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 26.0
        let sy = rect.height / 28.0
        var path = Path()
        // Right chevron
        path.move(to: CGPoint(x: 23.475 * sx, y: 25.75 * sy))
        path.addLine(to: CGPoint(x: 11.475 * sx, y: 13.9949 * sy))
        path.addLine(to: CGPoint(x: 23.475 * sx, y: 1.75 * sy))
        // Left chevron
        path.move(to: CGPoint(x: 14.475 * sx, y: 25.75 * sy))
        path.addLine(to: CGPoint(x: 2.475 * sx, y: 13.9949 * sy))
        path.addLine(to: CGPoint(x: 14.475 * sx, y: 1.75 * sy))
        return path
    }
}

// MARK: - Forward Arrow Shape (double chevron pointing right)

private struct ForwardArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 26.0
        let sy = rect.height / 28.0
        var path = Path()
        // Left chevron
        path.move(to: CGPoint(x: 1.75 * sx, y: 25.75 * sy))
        path.addLine(to: CGPoint(x: 13.75 * sx, y: 13.9949 * sy))
        path.addLine(to: CGPoint(x: 1.75 * sx, y: 1.75 * sy))
        // Right chevron
        path.move(to: CGPoint(x: 10.75 * sx, y: 25.75 * sy))
        path.addLine(to: CGPoint(x: 22.75 * sx, y: 13.9949 * sy))
        path.addLine(to: CGPoint(x: 10.75 * sx, y: 1.75 * sy))
        return path
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()

        VStack {
            Spacer()

            HStack(spacing: 0) {
                Text("Spr")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                Text("i")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .foregroundColor(.red)
                Text("tz")
                    .font(.system(size: 32, weight: .medium, design: .serif))
            }

            Spacer()

            LiquidGlassSpeedDial(
                wpm: .constant(420),
                isPlaying: .constant(false),
                onPlayPauseToggle: {},
                onRewind: {},
                onForwardSentence: {},
                onAddBookmark: {}
            )
            .padding(.bottom, 20)
        }
    }
}
