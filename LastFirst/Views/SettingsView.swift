import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showLiquidGlassLab = false

    var body: some View {
        NavigationStack {
            Form {
                // Reading Settings
                Section("Reading") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Default Speed")
                            Spacer()
                            Text("\(appState.settings.defaultWPM) WPM")
                                .foregroundColor(.secondary)
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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Paragraph Breath")
                            Spacer()
                            Text("\(appState.settings.paragraphBreathMs)ms")
                                .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Soft Start")
                            Spacer()
                            Text("\(Int(appState.settings.softStartPercentage * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $appState.settings.softStartPercentage,
                            in: 0.1...1.0,
                            step: 0.05
                        )
                        Text("Start at this percentage of target speed, ramping up over 1 minute")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Default Mode", selection: $appState.settings.defaultReadingMode) {
                        ForEach(ReadingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                }

                // Developer
                Section("Developer") {
                    Button {
                        showLiquidGlassLab = true
                    } label: {
                        HStack {
                            Label("Liquid Glass Lab", systemImage: "sparkles")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://lastfirst.app")!) {
                        HStack {
                            Text("Website")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                }
            }
            .sheet(isPresented: $showLiquidGlassLab) {
                LiquidGlassTestView()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(appState.settings.appearanceMode.preferredColorScheme)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
