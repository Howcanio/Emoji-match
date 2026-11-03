import EmojiMatchCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.sound) private var sound = true
    @AppStorage(SettingsKeys.haptics) private var haptics = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Sound", isOn: $sound)
                    .accessibilityIdentifier("soundToggle")
                Toggle("Haptics", isOn: $haptics)
                    .accessibilityIdentifier("hapticsToggle")
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .tint(Theme.pink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settingsDone")
                }
            }
        }
    }
}
