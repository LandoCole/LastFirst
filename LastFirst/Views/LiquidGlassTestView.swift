//
//  LiquidGlassTestView.swift
//  LastFirst
//
//  iOS 26 Liquid Glass Component Test Page
//  This view is for refining and testing Liquid Glass implementations
//  with backward compatibility for iOS 17/18
//

import SwiftUI

// MARK: - Backward Compatibility Extensions

extension View {
    /// Applies glass effect on iOS 26+, falls back to material on earlier versions
    @ViewBuilder
    func glassedBackground(
        in shape: some Shape = Capsule(),
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass = interactive ? Glass.regular.interactive() : .regular
            self.glassEffect(glass, in: shape)
        } else {
            self.background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 0.5))
            )
        }
    }

    /// Applies tinted glass effect with fallback
    @ViewBuilder
    func tintedGlassBackground(
        _ tint: Color,
        in shape: some Shape = Capsule(),
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(Glass.regular.tint(tint).interactive(), in: shape)
            } else {
                self.glassEffect(Glass.regular.tint(tint), in: shape)
            }
        } else {
            self.background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(tint.opacity(0.2))
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(shape.stroke(tint.opacity(0.3), lineWidth: 0.5))
            )
        }
    }
}

// MARK: - Glass Button Style (iOS 17/18 Fallback)

struct CompatibleGlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isProminent ? .thinMaterial : .ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Main Test View

struct LiquidGlassTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = 0
    @State private var showFloatingActions = false
    @State private var isPlaying = false
    @State private var speed: Double = 300
    @State private var showSheet = false

    @Namespace private var morphingNamespace

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient for testing glass visibility
                backgroundGradient

                ScrollView {
                    VStack(spacing: 32) {
                        sectionPicker

                        switch selectedSection {
                        case 0:
                            basicGlassSection
                        case 1:
                            buttonStylesSection
                        case 2:
                            morphingSection
                        case 3:
                            controlsSection
                        case 4:
                            toolbarTestSection
                        default:
                            EmptyView()
                        }

                        Spacer(minLength: 100)
                    }
                    .padding()
                }

                // Floating action button overlay
                floatingActionOverlay
            }
            .navigationTitle("Liquid Glass Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Info", systemImage: "info.circle") {
                        showSheet = true
                    }
                }
            }
            .sheet(isPresented: $showSheet) {
                glassInfoSheet
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.3),
                Color.purple.opacity(0.4),
                Color.pink.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5) { index in
                    let titles = ["Basic", "Buttons", "Morphing", "Controls", "Toolbar"]
                    sectionTab(title: titles[index], index: index)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func sectionTab(title: String, index: Int) -> some View {
        Button {
            withAnimation(.bouncy) {
                selectedSection = index
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selectedSection == index ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .glassedBackground(in: Capsule(), interactive: true)
        .overlay {
            if selectedSection == index {
                Capsule()
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }

    // MARK: - Section 1: Basic Glass Effects

    private var basicGlassSection: some View {
        VStack(spacing: 24) {
            sectionHeader("Basic Glass Effects")

            // Simple glass text
            VStack(spacing: 16) {
                Text("Regular Glass")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding()
                    .glassedBackground(in: RoundedRectangle(cornerRadius: 16))

                Text("Interactive Glass")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding()
                    .glassedBackground(in: Capsule(), interactive: true)

                // Tinted variations
                HStack(spacing: 12) {
                    tintedGlassLabel("Blue", tint: .blue)
                    tintedGlassLabel("Purple", tint: .purple)
                    tintedGlassLabel("Orange", tint: .orange)
                }
            }

            // Icon buttons with glass
            VStack(spacing: 16) {
                Text("Glass Icon Buttons")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    ForEach(["house", "gear", "book", "heart"], id: \.self) { icon in
                        glassIconButton(systemName: icon)
                    }
                }
            }
        }
    }

    private func tintedGlassLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .tintedGlassBackground(tint, in: Capsule())
    }

    private func glassIconButton(systemName: String) -> some View {
        Button {
            // Action
        } label: {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 50, height: 50)
        }
        .glassedBackground(in: Circle(), interactive: true)
    }

    // MARK: - Section 2: Button Styles

    private var buttonStylesSection: some View {
        VStack(spacing: 24) {
            sectionHeader("Button Styles")

            VStack(spacing: 16) {
                // iOS 26 native styles
                if #available(iOS 26.0, *) {
                    Text("iOS 26 Native Styles")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Button("Glass") { }
                            .buttonStyle(.glass)

                        Button("Prominent") { }
                            .buttonStyle(.glassProminent)
                            .tint(.blue)
                    }

                    HStack(spacing: 12) {
                        Button("Small", systemImage: "star") { }
                            .buttonStyle(.glass)
                            .controlSize(.small)

                        Button("Large", systemImage: "star.fill") { }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                    }
                }

                // Fallback styles (always shown for comparison)
                Text("Compatible Fallback Styles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                HStack(spacing: 16) {
                    Button("Glass") { }
                        .buttonStyle(CompatibleGlassButtonStyle())

                    Button("Prominent") { }
                        .buttonStyle(CompatibleGlassButtonStyle(isProminent: true))
                }

                // Circular buttons
                Text("Circular Buttons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                HStack(spacing: 16) {
                    circularButton("play.fill", color: .green)
                    circularButton("pause.fill", color: .orange)
                    circularButton("stop.fill", color: .red)
                }
            }
        }
    }

    private func circularButton(_ systemName: String, color: Color) -> some View {
        Button {
            // Action
        } label: {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .tintedGlassBackground(color, in: Circle(), interactive: true)
    }

    // MARK: - Section 3: Morphing Transitions

    private var morphingSection: some View {
        VStack(spacing: 24) {
            sectionHeader("Morphing Transitions")

            Text("Tap the button to see morphing animation")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Morphing demo
            morphingDemo
        }
    }

    private var morphingDemo: some View {
        VStack(spacing: 20) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 20) {
                    VStack(spacing: 16) {
                        if showFloatingActions {
                            ForEach(["photo", "video", "doc.text"], id: \.self) { icon in
                                morphingActionButton(icon: icon)
                                    .glassEffectID(icon, in: morphingNamespace)
                            }
                        }

                        Button {
                            withAnimation(.bouncy(duration: 0.4)) {
                                showFloatingActions.toggle()
                            }
                        } label: {
                            Image(systemName: showFloatingActions ? "xmark" : "plus")
                                .font(.title2.bold())
                                .frame(width: 56, height: 56)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(.blue)
                        .glassEffectID("toggle", in: morphingNamespace)
                    }
                }
            } else {
                // Fallback for iOS 17/18 - simpler animation without morphing
                VStack(spacing: 16) {
                    if showFloatingActions {
                        ForEach(["photo", "video", "doc.text"], id: \.self) { icon in
                            morphingActionButtonFallback(icon: icon)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showFloatingActions.toggle()
                        }
                    } label: {
                        Image(systemName: showFloatingActions ? "xmark" : "plus")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                    }
                    .tintedGlassBackground(.blue, in: Circle(), interactive: true)
                }
            }
        }
        .frame(height: 280)
    }

    @available(iOS 26.0, *)
    private func morphingActionButton(icon: String) -> some View {
        Button { } label: {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private func morphingActionButtonFallback(icon: String) -> some View {
        Button { } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
        }
        .glassedBackground(in: Circle(), interactive: true)
    }

    // MARK: - Section 4: Controls

    private var controlsSection: some View {
        VStack(spacing: 24) {
            sectionHeader("Glass Controls")

            // Play/Pause toggle
            VStack(spacing: 16) {
                Text("Playback Control")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.bouncy) {
                        isPlaying.toggle()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.primary)
                        .frame(width: 80, height: 80)
                        .contentTransition(.symbolEffect(.replace))
                }
                .glassedBackground(in: Circle(), interactive: true)
            }

            // Speed control
            VStack(spacing: 16) {
                Text("Speed: \(Int(speed)) WPM")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .glassedBackground(in: Capsule())

                HStack(spacing: 20) {
                    Button {
                        withAnimation { speed = max(100, speed - 50) }
                    } label: {
                        Image(systemName: "minus")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .glassedBackground(in: Circle(), interactive: true)

                    // Speed slider track
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .frame(height: 8)

                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: CGFloat((speed - 100) / 700) * geo.size.width, height: 8)
                        }
                    }
                    .frame(height: 44)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let percent = value.location.x / 200
                                speed = min(800, max(100, 100 + Double(percent) * 700))
                            }
                    )

                    Button {
                        withAnimation { speed = min(800, speed + 50) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .glassedBackground(in: Circle(), interactive: true)
                }
                .frame(width: 280)
            }

            // Segmented control style
            VStack(spacing: 16) {
                Text("Mode Selector")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                glassSegmentedControl
            }
        }
    }

    @State private var selectedMode = 0

    private var glassSegmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                let labels = ["Spritz", "Stream", "Scan"]
                let icons = ["text.word.spacing", "text.alignleft", "doc.text"]

                Button {
                    withAnimation(.bouncy) {
                        selectedMode = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icons[index])
                            .font(.title3)
                        Text(labels[index])
                            .font(.caption2)
                    }
                    .foregroundStyle(selectedMode == index ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .background {
                    if selectedMode == index {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                }
            }
        }
        .padding(4)
        .glassedBackground(in: RoundedRectangle(cornerRadius: 16))
        .frame(width: 280)
    }

    // MARK: - Section 5: Toolbar Test

    private var toolbarTestSection: some View {
        VStack(spacing: 24) {
            sectionHeader("Toolbar Integration")

            Text("The navigation bar above demonstrates glass toolbar styling")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                Text("Bottom Bar Example")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Simulated bottom toolbar
                HStack(spacing: 20) {
                    ForEach(["pencil", "eraser", "paintbrush"], id: \.self) { icon in
                        glassToolbarButton(icon: icon)
                    }

                    Spacer()

                    // Prominent action
                    Button {
                        // Save action
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .tintedGlassBackground(.green, in: Circle(), interactive: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassedBackground(in: Capsule())
            }
        }
    }

    private func glassToolbarButton(icon: String) -> some View {
        Button { } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .glassedBackground(in: Circle(), interactive: true)
    }

    // MARK: - Floating Action Overlay

    private var floatingActionOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                // Mini floating action button
                Button {
                    // Quick action
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                }
                .tintedGlassBackground(.purple, in: Circle(), interactive: true)
                .shadow(color: .purple.opacity(0.3), radius: 10, y: 5)
            }
            .padding()
        }
    }

    // MARK: - Info Sheet

    private var glassInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    infoSection(
                        title: "Liquid Glass Overview",
                        content: "iOS 26 introduces Liquid Glass, a translucent material that bends light in real-time. It's designed for navigation layers floating above content."
                    )

                    infoSection(
                        title: "Backward Compatibility",
                        content: "This test page uses helper extensions that fall back to ultraThinMaterial on iOS 17/18 while using native glass effects on iOS 26+."
                    )

                    infoSection(
                        title: "Key Components",
                        content: """
                        - glassEffect() - Basic glass modifier
                        - GlassEffectContainer - Groups glass elements
                        - .buttonStyle(.glass) - Glass button style
                        - glassEffectID - Enables morphing transitions
                        """
                    )

                    infoSection(
                        title: "Design Guidelines",
                        content: """
                        - Only use glass for navigation/controls
                        - Never apply to content (lists, images)
                        - Use tinting selectively for primary actions
                        - Group related glass elements in containers
                        """
                    )
                }
                .padding()
            }
            .navigationTitle("Liquid Glass Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func infoSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    LiquidGlassTestView()
}
