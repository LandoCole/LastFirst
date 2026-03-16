import SwiftUI

struct ThemesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showCustomizePanel: Bool = false
    @State private var showSettingsPanel: Bool = false
    @State private var selectedDetent: PresentationDetent = .height(520)
    @State private var deviceBrightness: CGFloat = UIScreen.main.brightness
    @State private var currentThemePage: Int = 0
    @State private var showDeleteConfirmation: Bool = false
    @State private var customThemeToDelete: UUID? = nil
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
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: width / 2, style: .continuous))
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
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: width / 2, style: .continuous))
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
        let themeSettings = appState.settings.readerThemeSettings
        let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)

        switch themeSettings.selectedThemeID {
        case .preset(let preset):
            if let override = themeSettings.override(for: preset),
               override.isEnabled, let font = override.font {
                return font
            }
            return ReaderThemeSettings.defaultTheme(for: preset, variant: variant).font
        case .custom(let uuid):
            if let custom = themeSettings.customThemes.first(where: { $0.id == uuid }) {
                return (variant == .light ? custom.lightDefinition : custom.darkDefinition).font
            }
            return ReaderThemeSettings.defaultTheme(for: .original, variant: variant).font
        }
    }

    private func selectFont(_ font: ReaderFont) {
        var themeSettings = appState.settings.readerThemeSettings
        switch themeSettings.selectedThemeID {
        case .preset(let preset):
            var override = themeSettings.override(for: preset)
                ?? ReaderThemeOverride(isEnabled: true, font: nil, bold: nil, lineSpacing: nil, letterSpacing: nil, wordSpacing: nil, margin: nil, textJustified: nil)
            override.isEnabled = true
            override.font = font
            themeSettings.setOverride(override, for: preset)
        case .custom(let uuid):
            if let index = themeSettings.customThemes.firstIndex(where: { $0.id == uuid }) {
                let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
                if variant == .light {
                    let def = themeSettings.customThemes[index].lightDefinition
                    themeSettings.customThemes[index].lightDefinition = ReaderThemeDefinition(
                        backgroundColorHex: def.backgroundColorHex, textColorHex: def.textColorHex,
                        secondaryTextColorHex: def.secondaryTextColorHex, linkColorHex: def.linkColorHex,
                        pattern: def.pattern, font: font, bold: def.bold,
                        lineSpacing: def.lineSpacing, letterSpacing: def.letterSpacing,
                        wordSpacing: def.wordSpacing, margin: def.margin, textJustified: def.textJustified
                    )
                } else {
                    let def = themeSettings.customThemes[index].darkDefinition
                    themeSettings.customThemes[index].darkDefinition = ReaderThemeDefinition(
                        backgroundColorHex: def.backgroundColorHex, textColorHex: def.textColorHex,
                        secondaryTextColorHex: def.secondaryTextColorHex, linkColorHex: def.linkColorHex,
                        pattern: def.pattern, font: font, bold: def.bold,
                        lineSpacing: def.lineSpacing, letterSpacing: def.letterSpacing,
                        wordSpacing: def.wordSpacing, margin: def.margin, textJustified: def.textJustified
                    )
                }
            }
        }
        appState.settings.readerThemeSettings = themeSettings
    }

    // MARK: - Theme Card Items

    private enum ThemeCardItem: Identifiable {
        case preset(ReaderThemePresetID)
        case custom(CustomTheme)
        case addNew

        var id: String {
            switch self {
            case .preset(let p): return "preset_\(p.rawValue)"
            case .custom(let c): return "custom_\(c.id.uuidString)"
            case .addNew: return "add_new"
            }
        }
    }

    private var themeCardItems: [ThemeCardItem] {
        var items: [ThemeCardItem] = ReaderThemePresetID.allCases.map { .preset($0) }
        items += appState.settings.readerThemeSettings.customThemes.map { .custom($0) }
        items.append(.addNew)
        return items
    }

    // MARK: - Theme Presets Section

    private var presetsSection: some View {
        let allCards = themeCardItems
        let pages = allCards.chunked(into: 6)

        return VStack(spacing: 8) {
            TabView(selection: $currentThemePage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, pageCards in
                    LazyVGrid(columns: presetColumns, spacing: 8) {
                        ForEach(pageCards) { card in
                            themeCardView(for: card)
                        }
                    }
                    .padding(10)
                    .tag(pageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 200)

            if pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentThemePage ? Color.primary : Color.primary.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .alert("Delete Theme?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { customThemeToDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = customThemeToDelete {
                    appState.settings.readerThemeSettings.deleteCustomTheme(id: id)
                    customThemeToDelete = nil
                }
            }
        } message: {
            Text("This custom theme will be permanently removed.")
        }
    }

    @ViewBuilder
    private func themeCardView(for card: ThemeCardItem) -> some View {
        let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
        switch card {
        case .preset(let preset):
            let definition = ReaderThemeSettings.defaultTheme(for: preset, variant: variant)
            let isSelected = appState.settings.readerThemeSettings.selectedThemeID == .preset(preset)
            ThemePresetCard(
                name: preset.displayName,
                definition: definition,
                isSelected: isSelected
            )
            .onTapGesture {
                withAnimation(.bouncy(duration: 0.35)) {
                    appState.settings.readerThemeSettings.selectedThemeID = .preset(preset)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

        case .custom(let custom):
            let definition = variant == .light ? custom.lightDefinition : custom.darkDefinition
            let isSelected = appState.settings.readerThemeSettings.selectedThemeID == .custom(custom.id)
            ThemePresetCard(
                name: custom.name,
                definition: definition,
                isSelected: isSelected
            )
            .onTapGesture {
                withAnimation(.bouncy(duration: 0.35)) {
                    appState.settings.readerThemeSettings.selectedThemeID = .custom(custom.id)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .contextMenu {
                Button(role: .destructive) {
                    customThemeToDelete = custom.id
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

        case .addNew:
            ThemeAddCard()
                .onTapGesture {
                    addNewCustomTheme()
                }
        }
    }

    private func addNewCustomTheme() {
        let currentThemeID = appState.settings.readerThemeSettings.selectedThemeID

        let lightDef: ReaderThemeDefinition
        let darkDef: ReaderThemeDefinition

        switch currentThemeID {
        case .preset(let presetID):
            lightDef = ReaderThemeSettings.defaultTheme(for: presetID, variant: .light)
            darkDef = ReaderThemeSettings.defaultTheme(for: presetID, variant: .dark)
        case .custom(let uuid):
            if let existing = appState.settings.readerThemeSettings.customThemes.first(where: { $0.id == uuid }) {
                lightDef = existing.lightDefinition
                darkDef = existing.darkDefinition
            } else {
                lightDef = ReaderThemeSettings.defaultTheme(for: .original, variant: .light)
                darkDef = ReaderThemeSettings.defaultTheme(for: .original, variant: .dark)
            }
        }

        let count = appState.settings.readerThemeSettings.customThemes.count + 1
        let custom = CustomTheme(
            id: UUID(),
            name: "Custom \(count)",
            lightDefinition: lightDef,
            darkDefinition: darkDef
        )
        appState.settings.readerThemeSettings.addCustomTheme(custom)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                // Custom theme editing controls
                if case .custom(let uuid) = appState.settings.readerThemeSettings.selectedThemeID,
                   let customIndex = appState.settings.readerThemeSettings.customThemes.firstIndex(where: { $0.id == uuid }) {
                    let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)

                    TextField("Theme Name", text: Binding(
                        get: { appState.settings.readerThemeSettings.customThemes[customIndex].name },
                        set: { appState.settings.readerThemeSettings.customThemes[customIndex].name = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    ColorPicker("Background", selection: Binding(
                        get: {
                            let hex = variant == .light
                                ? appState.settings.readerThemeSettings.customThemes[customIndex].lightDefinition.backgroundColorHex
                                : appState.settings.readerThemeSettings.customThemes[customIndex].darkDefinition.backgroundColorHex
                            return Color(hex: hex)
                        },
                        set: { newColor in
                            let hex = newColor.toHex()
                            if variant == .light {
                                let def = appState.settings.readerThemeSettings.customThemes[customIndex].lightDefinition
                                appState.settings.readerThemeSettings.customThemes[customIndex].lightDefinition = ReaderThemeDefinition(
                                    backgroundColorHex: hex, textColorHex: def.textColorHex,
                                    secondaryTextColorHex: def.secondaryTextColorHex, linkColorHex: def.linkColorHex,
                                    pattern: def.pattern, font: def.font, bold: def.bold,
                                    lineSpacing: def.lineSpacing, letterSpacing: def.letterSpacing,
                                    wordSpacing: def.wordSpacing, margin: def.margin, textJustified: def.textJustified
                                )
                            } else {
                                let def = appState.settings.readerThemeSettings.customThemes[customIndex].darkDefinition
                                appState.settings.readerThemeSettings.customThemes[customIndex].darkDefinition = ReaderThemeDefinition(
                                    backgroundColorHex: hex, textColorHex: def.textColorHex,
                                    secondaryTextColorHex: def.secondaryTextColorHex, linkColorHex: def.linkColorHex,
                                    pattern: def.pattern, font: def.font, bold: def.bold,
                                    lineSpacing: def.lineSpacing, letterSpacing: def.letterSpacing,
                                    wordSpacing: def.wordSpacing, margin: def.margin, textJustified: def.textJustified
                                )
                            }
                        }
                    ), supportsOpacity: false)

                    ColorPicker("Text", selection: Binding(
                        get: {
                            let hex = variant == .light
                                ? appState.settings.readerThemeSettings.customThemes[customIndex].lightDefinition.textColorHex
                                : appState.settings.readerThemeSettings.customThemes[customIndex].darkDefinition.textColorHex
                            return Color(hex: hex)
                        },
                        set: { newColor in
                            let hex = newColor.toHex()
                            if variant == .light {
                                let def = appState.settings.readerThemeSettings.customThemes[customIndex].lightDefinition
                                appState.settings.readerThemeSettings.customThemes[customIndex].lightDefinition = ReaderThemeDefinition(
                                    backgroundColorHex: def.backgroundColorHex, textColorHex: hex,
                                    secondaryTextColorHex: def.secondaryTextColorHex, linkColorHex: def.linkColorHex,
                                    pattern: def.pattern, font: def.font, bold: def.bold,
                                    lineSpacing: def.lineSpacing, letterSpacing: def.letterSpacing,
                                    wordSpacing: def.wordSpacing, margin: def.margin, textJustified: def.textJustified
                                )
                            } else {
                                let def = appState.settings.readerThemeSettings.customThemes[customIndex].darkDefinition
                                appState.settings.readerThemeSettings.customThemes[customIndex].darkDefinition = ReaderThemeDefinition(
                                    backgroundColorHex: def.backgroundColorHex, textColorHex: hex,
                                    secondaryTextColorHex: def.secondaryTextColorHex, linkColorHex: def.linkColorHex,
                                    pattern: def.pattern, font: def.font, bold: def.bold,
                                    lineSpacing: def.lineSpacing, letterSpacing: def.letterSpacing,
                                    wordSpacing: def.wordSpacing, margin: def.margin, textJustified: def.textJustified
                                )
                            }
                        }
                    ), supportsOpacity: false)

                    Divider()
                }

                Toggle("Bold Text", isOn: boldBinding)
                Toggle("Justify Text", isOn: justifiedBinding)
                    .disabled(currentThemeDisablesJustification)

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

                // Restore defaults button (only for presets with overrides)
                if shouldShowRestoreButton {
                    Button {
                        if case .preset(let presetID) = appState.settings.readerThemeSettings.selectedThemeID {
                            appState.settings.readerThemeSettings.resetOverride(for: presetID)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .medium))
                            Text("Restore Defaults")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var shouldShowRestoreButton: Bool {
        guard case .preset(let presetID) = appState.settings.readerThemeSettings.selectedThemeID else { return false }
        return appState.settings.readerThemeSettings.override(for: presetID)?.isEnabled == true
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

    private var currentThemeDisablesJustification: Bool {
        let variant = appState.settings.appearanceMode.resolvedVariant(systemScheme: colorScheme)
        let themeSettings = appState.settings.readerThemeSettings
        switch themeSettings.selectedThemeID {
        case .preset(let p):
            return ReaderThemeSettings.defaultTheme(for: p, variant: variant).pattern.disablesJustification
        case .custom(let uuid):
            guard let c = themeSettings.customThemes.first(where: { $0.id == uuid }) else { return false }
            return (variant == .light ? c.lightDefinition : c.darkDefinition).pattern.disablesJustification
        }
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
    let name: String
    let definition: ReaderThemeDefinition
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(size: 28, weight: .medium, design: definition.font.swiftUIDesign))
                    .foregroundColor(Color(hex: definition.textColorHex))

                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: definition.textColorHex))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 85)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: definition.backgroundColorHex))
                    .overlay {
                        ThemePatternOverlay(
                            pattern: definition.pattern,
                            variant: .light,
                            compact: true
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
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

// MARK: - Theme Add Card

private struct ThemeAddCard: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            Text("New")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 85)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.primary.opacity(0.15))
        }
    }
}

// MARK: - Array Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
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
