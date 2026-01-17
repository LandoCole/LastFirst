import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Appearance
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $appState.settings.isDarkMode)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(appState.settings.fontSize))pt")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $appState.settings.fontSize,
                            in: 16...48,
                            step: 2
                        )
                    }

                    // Preview
                    HStack {
                        Spacer()
                        Text("Sample")
                            .font(.system(size: appState.settings.fontSize, design: .serif))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

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
                    
                    Picker("Speed Control", selection: $appState.settings.dialStyle) {
                        ForEach(DialStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    
                    Picker("Auto-Hide Dial", selection: $appState.settings.autoHideDialDelay) {
                        ForEach(AutoHideDialDelay.allCases, id: \.self) { delay in
                            Text(delay.displayName).tag(delay)
                        }
                    }
                    Text("In Stream/Scan modes, hide dial after inactivity")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(appState.settings.isDarkMode ? .dark : .light)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
