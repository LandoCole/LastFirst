import SwiftUI

struct ThemesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showCustomizePanel: Bool = false
    @State private var showSettingsPanel: Bool = false
    @State private var selectedDetent: PresentationDetent = .height(520)
    @State private var deviceBrightness: CGFloat = UIScreen.main.brightness
    @Namespace private var glassNamespace

    private let presetColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    // Font size steps (12 steps from min to max)
    private var fontSizeSteps: [CGFloat] {
        let min = ReaderThemeSettings.minFontSize
        let max = ReaderThemeSettings.maxFontSize
        let step = (max - min) / 11.0
        return (0..<12).map { min + CGFloat($0) * step }
    }

    private var currentFontSizeIndex: Int {
        let fontSize = appState.settings.fontSize
        return fontSizeSteps.enumerated().min(by: {
            abs($0.element - fontSize) < abs($1.element - fontSize)
        })?.offset ?? 6
    }

    private var fontSizeFillPercent: CGFloat {
        CGFloat(currentFontSizeIndex) / 11.0
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Row 1: Top controls (4 columns)
                topControlsRow

                // Row 2: Theme presets grid
                presetsSection

                // Row 3: Customize button / panel
                customizeSection

                // Row 4: Settings button / panel
                settingsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .presentationDetents([.height(520), .large], selection: $selectedDetent)
        .onChange(of: showCustomizePanel) { _, isOpen in
            withAnimation(.bouncy(duration: 0.35)) {
                selectedDetent = isOpen ? .large : .height(520)
            }
        }
        .onChange(of: showSettingsPanel) { _, isOpen in
            withAnimation(.bouncy(duration: 0.35)) {
                selectedDetent = isOpen ? .large : .height(520)
            }
        }
    }

    // MARK: - Top Controls Row

    @ViewBuilder
    private var topControlsRow: some View {
        let pillHeight: CGFloat = 160
        let pillWidth: CGFloat = 70
        let horizontalButtonHeight: CGFloat = (pillHeight - 12) / 2  // Half height minus spacing

        // 3-column layout: Brightness | Font Size | Mode/Font stacked
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    // Column 1: Brightness slider (vertical)
                    brightnessSlider(width: pillWidth, height: pillHeight)
                    
                    // Column 2: Font Size stepper (vertical)
                    fontSizeStepper(width: pillWidth, height: pillHeight)
                    
                    // Column 3: Mode + Font buttons stacked (horizontal orientation)
                    VStack(spacing: 12) {
                        appearanceModeButton(width: pillHeight, height: horizontalButtonHeight)
                        fontSelectorButton(width: pillHeight, height: horizontalButtonHeight)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                // Column 1: Brightness slider (vertical)
                brightnessSlider(width: pillWidth, height: pillHeight)
                
                // Column 2: Font Size stepper (vertical)
                fontSizeStepper(width: pillWidth, height: pillHeight)
                
                // Column 3: Mode + Font buttons stacked (horizontal orientation)
                VStack(spacing: 12) {
                    appearanceModeButton(width: pillHeight, height: horizontalButtonHeight)
                    fontSelectorButton(width: pillHeight, height: horizontalButtonHeight)
                }
            }
        }
    }

    // MARK: - Brightness Slider

    @ViewBuilder
    private func brightnessSlider(width: CGFloat, height: CGFloat) -> some View {
        let cornerRadius = width / 2
        
        ZStack(alignment: .bottom) {
            // Track background
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
            
            // Fill - aligned to bottom, height based on percentage
            // Device brightness ranges from 0 to 1
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(height: max(0, height * deviceBrightness))
            
            // Sun icon
            VStack {
                Spacer()
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.yellow)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let percent = 1.0 - (value.location.y / height)
                    let newBrightness = min(1.0, max(0.0, percent))
                    deviceBrightness = newBrightness
                    UIScreen.main.brightness = newBrightness
                }
        )
        .glassedPill()
        .onAppear {
            deviceBrightness = UIScreen.main.brightness
        }
    }

    // MARK: - Font Size Stepper

    @ViewBuilder
    private func fontSizeStepper(width: CGFloat, height: CGFloat) -> some View {
        let cornerRadius = width / 2
        
        ZStack(alignment: .bottom) {
            // Track background
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
            
            // Fill - aligned to bottom, height based on font size index
            // Use Rectangle and let parent clipShape handle corner rounding
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(height: height * fontSizeFillPercent)
            
            // Buttons and divider
            VStack(spacing: 0) {
                Button { adjustFontSize(delta: 1) } label: {
                    Text("A")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                
                Button { adjustFontSize(delta: -1) } label: {
                    Text("A")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .glassedPill()
    }

    private func adjustFontSize(delta: Int) {
        let newIndex = max(0, min(11, currentFontSizeIndex + delta))
        appState.settings.fontSize = fontSizeSteps[newIndex]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Appearance Mode Button

    @ViewBuilder
    private func appearanceModeButton(width: CGFloat, height: CGFloat) -> some View {
        let buttonContent = HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: iconForAppearance(appState.settings.appearanceMode))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Mode")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(appState.settings.appearanceMode.shortName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: height)
        
        if #available(iOS 26.0, *) {
            Menu {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        appState.settings.appearanceMode = mode
                    } label: {
                        Label(mode.displayName, systemImage: iconForAppearance(mode))
                    }
                }
            } label: {
                buttonContent
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: width / 2, style: .continuous))
            .glassEffectID("modeButton", in: glassNamespace)
            .tint(.primary)
        } else {
            Menu {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        appState.settings.appearanceMode = mode
                    } label: {
                        Label(mode.displayName, systemImage: iconForAppearance(mode))
                    }
                }
            } label: {
                buttonContent
            }
            .background {
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .tint(.primary)
        }
    }

    private func iconForAppearance(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    // MARK: - Font Selector Button

    @ViewBuilder
    private func fontSelectorButton(width: CGFloat, height: CGFloat) -> some View {
        let buttonContent = HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay {
                    Text("Aa")
                        .font(.system(size: 16, weight: .semibold, design: currentFont.swiftUIDesign))
                        .foregroundStyle(.primary)
                }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Font")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(currentFont.shortName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: height)
        
        if #available(iOS 26.0, *) {
            Menu {
                ForEach(ReaderFont.allCases) { font in
                    Button {
                        selectFont(font)
                    } label: {
                        HStack {
                            Text(font.displayName)
                            if currentFont == font {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                buttonContent
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: width / 2, style: .continuous))
            .glassEffectID("fontButton", in: glassNamespace)
            .tint(.primary)
        } else {
            Menu {
                ForEach(ReaderFont.allCases) { font in
                    Button {
                        selectFont(font)
                    } label: {
                        HStack {
                            Text(font.displayName)
                            if currentFont == font {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                buttonContent
            }
            .background {
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .tint(.primary)
        }
    }

    private var currentFont: ReaderFont {
        let preset = appState.settings.readerThemeSettings.selectedPreset
        if let override = appState.settings.readerThemeSettings.override(for: preset),
           override.isEnabled, let font = override.font {
            return font
        }
        let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
        return ReaderThemeSettings.defaultTheme(for: preset, variant: variant).font
    }

    private func selectFont(_ font: ReaderFont) {
        var themeSettings = appState.settings.readerThemeSettings
        let preset = themeSettings.selectedPreset
        var override = themeSettings.override(for: preset)
            ?? ReaderThemeOverride(isEnabled: true, font: nil, bold: nil, lineSpacing: nil, letterSpacing: nil, wordSpacing: nil, margin: nil, textJustified: nil)
        override.isEnabled = true
        override.font = font
        themeSettings.setOverride(override, for: preset)
        appState.settings.readerThemeSettings = themeSettings
    }

    // MARK: - Theme Presets Section

    private var presetsSection: some View {
        LazyVGrid(columns: presetColumns, spacing: 8) {
            ForEach(ReaderThemePresetID.allCases) { preset in
                let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
                let definition = ReaderThemeSettings.defaultTheme(for: preset, variant: variant)
                let isSelected = preset == appState.settings.readerThemeSettings.selectedPreset

                ThemePresetCard(preset: preset, definition: definition, isSelected: isSelected)
                    .onTapGesture {
                        withAnimation(.bouncy(duration: 0.35)) {
                            appState.settings.readerThemeSettings.selectedPreset = preset
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }

    // MARK: - Customize Section

    @ViewBuilder
    private var customizeSection: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 20) {
                if showCustomizePanel {
                    expandedCustomizePanelContent
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .glassEffectID("customize", in: glassNamespace)
                } else {
                    collapsedCustomizeButtonContent
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.bouncy(duration: 0.35)) {
                                showCustomizePanel = true
                            }
                        }
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .glassEffectID("customize", in: glassNamespace)
                }
            }
            .animation(.bouncy(duration: 0.35), value: showCustomizePanel)
        } else {
            VStack(spacing: 0) {
                if showCustomizePanel {
                    expandedCustomizePanel
                } else {
                    collapsedCustomizeButton
                }
            }
            .animation(.bouncy(duration: 0.35), value: showCustomizePanel)
        }
    }

    private var collapsedCustomizeButton: some View {
        Button {
            withAnimation(.bouncy(duration: 0.35)) { showCustomizePanel = true }
        } label: {
            collapsedCustomizeButtonContent
        }
        .glassedRect()
    }

    private var collapsedCustomizeButtonContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("Customize")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Accessibility Options")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var expandedCustomizePanel: some View {
        expandedCustomizePanelContent
            .glassedRect()
    }

    private var expandedCustomizePanelContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Customize")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Accessibility Options")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 6)

                Spacer()

                closeButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 14)

            // Controls
            VStack(spacing: 16) {
                Toggle("Bold Text", isOn: boldBinding)
                Toggle("Justify Text", isOn: justifiedBinding)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Margins")
                        Spacer()
                        Text("\(Int(marginBinding.wrappedValue))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: marginBinding, in: ReaderThemeSettings.minMargin...ReaderThemeSettings.maxMargin)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Line Spacing")
                        Spacer()
                        Text(String(format: "%.1f", lineSpacingBinding.wrappedValue))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: lineSpacingBinding, in: ReaderThemeSettings.minLineSpacing...ReaderThemeSettings.maxLineSpacing)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                withAnimation(.bouncy(duration: 0.35)) { showCustomizePanel = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        } else {
            Button {
                withAnimation(.bouncy(duration: 0.35)) { showCustomizePanel = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
        }
    }

    // MARK: - Settings Section

    @ViewBuilder
    private var settingsSection: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 20) {
                if showSettingsPanel {
                    expandedSettingsPanelContent
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .glassEffectID("settings", in: glassNamespace)
                } else {
                    collapsedSettingsButtonContent
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.bouncy(duration: 0.35)) {
                                showSettingsPanel = true
                            }
                        }
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .glassEffectID("settings", in: glassNamespace)
                }
            }
            .animation(.bouncy(duration: 0.35), value: showSettingsPanel)
        } else {
            VStack(spacing: 0) {
                if showSettingsPanel {
                    expandedSettingsPanel
                } else {
                    collapsedSettingsButton
                }
            }
            .animation(.bouncy(duration: 0.35), value: showSettingsPanel)
        }
    }

    private var collapsedSettingsButton: some View {
        Button {
            withAnimation(.bouncy(duration: 0.35)) { showSettingsPanel = true }
        } label: {
            collapsedSettingsButtonContent
        }
        .glassedRect()
    }

    private var collapsedSettingsButtonContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Reading Preferences")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var expandedSettingsPanel: some View {
        expandedSettingsPanelContent
            .glassedRect()
    }

    private var expandedSettingsPanelContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Reading Preferences")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 6)

                Spacer()

                settingsCloseButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 14)

            // Controls
            VStack(spacing: 16) {
                // Default Speed
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Default Speed")
                        Spacer()
                        Text("\(appState.settings.defaultWPM) WPM")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(appState.settings.defaultWPM) },
                            set: { appState.settings.defaultWPM = Int($0) }
                        ),
                        in: 50...1500,
                        step: 25
                    )
                }

                // Paragraph Breath
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Paragraph Breath")
                        Spacer()
                        Text("\(appState.settings.paragraphBreathMs)ms")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(appState.settings.paragraphBreathMs) },
                            set: { appState.settings.paragraphBreathMs = Int($0) }
                        ),
                        in: 0...1000,
                        step: 50
                    )
                    Text("Pause briefly on the last word of each paragraph")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Soft Start
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Soft Start")
                        Spacer()
                        Text("\(Int(appState.settings.softStartPercentage * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $appState.settings.softStartPercentage,
                        in: 0.1...1.0,
                        step: 0.05
                    )
                    Text("Start at this percentage of target speed, ramping up over 1 minute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Default Mode
                HStack {
                    Text("Default Mode")
                    Spacer()
                    Picker("", selection: $appState.settings.defaultReadingMode) {
                        ForEach(ReadingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }

            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var settingsCloseButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                withAnimation(.bouncy(duration: 0.35)) { showSettingsPanel = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        } else {
            Button {
                withAnimation(.bouncy(duration: 0.35)) { showSettingsPanel = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
        }
    }

    // MARK: - Bindings

    private var boldBinding: Binding<Bool> {
        Binding(
            get: {
                let preset = appState.settings.readerThemeSettings.selectedPreset
                if let override = appState.settings.readerThemeSettings.override(for: preset),
                   override.isEnabled, let bold = override.bold { return bold }
                let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
                return ReaderThemeSettings.defaultTheme(for: preset, variant: variant).bold
            },
            set: { updateOverride { $0.bold = $1 }($0) }
        )
    }

    private var justifiedBinding: Binding<Bool> {
        Binding(
            get: {
                let preset = appState.settings.readerThemeSettings.selectedPreset
                if let override = appState.settings.readerThemeSettings.override(for: preset),
                   override.isEnabled, let justified = override.textJustified { return justified }
                let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
                return ReaderThemeSettings.defaultTheme(for: preset, variant: variant).textJustified
            },
            set: { updateOverride { $0.textJustified = $1 }($0) }
        )
    }

    private var marginBinding: Binding<Double> {
        Binding(
            get: {
                let preset = appState.settings.readerThemeSettings.selectedPreset
                if let override = appState.settings.readerThemeSettings.override(for: preset),
                   override.isEnabled, let margin = override.margin { return margin }
                let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
                return ReaderThemeSettings.defaultTheme(for: preset, variant: variant).margin
            },
            set: { updateOverride { $0.margin = $1 }($0) }
        )
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(
            get: {
                let preset = appState.settings.readerThemeSettings.selectedPreset
                if let override = appState.settings.readerThemeSettings.override(for: preset),
                   override.isEnabled, let spacing = override.lineSpacing { return spacing }
                let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
                return ReaderThemeSettings.defaultTheme(for: preset, variant: variant).lineSpacing
            },
            set: { updateOverride { $0.lineSpacing = $1 }($0) }
        )
    }

    private func updateOverride<T>(_ update: @escaping (inout ReaderThemeOverride, T) -> Void) -> (T) -> Void {
        return { newValue in
            var themeSettings = appState.settings.readerThemeSettings
            let preset = themeSettings.selectedPreset
            var override = themeSettings.override(for: preset)
                ?? ReaderThemeOverride(isEnabled: true, font: nil, bold: nil, lineSpacing: nil, letterSpacing: nil, wordSpacing: nil, margin: nil, textJustified: nil)
            override.isEnabled = true
            update(&override, newValue)
            themeSettings.setOverride(override, for: preset)
            appState.settings.readerThemeSettings = themeSettings
        }
    }
}

// MARK: - Theme Preset Card

private struct ThemePresetCard: View {
    let preset: ReaderThemePresetID
    let definition: ReaderThemeDefinition
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(size: 28, weight: .medium, design: definition.font.swiftUIDesign))
                    .foregroundColor(Color(hex: definition.textColorHex))

                Text(preset.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: definition.textColorHex))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 85)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: definition.backgroundColorHex))
            }

            if isSelected {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .offset(x: -6, y: 6)
            }
        }
    }
}

// MARK: - Glass Pill Extension

private extension View {
    @ViewBuilder
    func glassedPill(interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = interactive ? .regular.interactive() : .regular
            self.glassEffect(glass, in: RoundedRectangle(cornerRadius: 100, style: .continuous))
        } else {
            self.background {
                RoundedRectangle(cornerRadius: 100, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    func glassedRect() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            self.background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

#Preview {
    ThemesSettingsView()
        .environmentObject(AppState())
}
