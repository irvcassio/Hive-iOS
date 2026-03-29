import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var config: HiveConfig
    @Environment(\.dismiss) private var dismiss
    @State private var showDisconnectAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Tunnel URL") {
                        Text(config.tunnelURL)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    LabeledContent("Client ID") {
                        Text(maskedString(config.clientId))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        showDisconnectAlert = true
                    }
                } footer: {
                    Text("This will clear all stored credentials and return to the setup screen.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Disconnect from Hive?", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    config.clear()
                    dismiss()
                }
            } message: {
                Text("You'll need to re-enter your tunnel URL and service token to reconnect.")
            }
        }
    }

    private func maskedString(_ value: String) -> String {
        guard value.count > 8 else { return String(repeating: "\u{2022}", count: value.count) }
        let prefix = String(value.prefix(4))
        let suffix = String(value.suffix(4))
        return "\(prefix)\u{2022}\u{2022}\u{2022}\u{2022}\(suffix)"
    }
}
