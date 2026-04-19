import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var config: HiveConfig
    @EnvironmentObject var networkResolver: NetworkResolver
    @Environment(\.dismiss) private var dismiss
    @State private var showDisconnectAlert = false
    @State private var lanHost: String = UserDefaults.standard.string(forKey: NetworkResolver.lanHostKey) ?? "hive.local"

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
                    HStack {
                        Text("LAN Host")
                        Spacer()
                        TextField("hive.local", text: $lanHost)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { saveLanHost() }
                    }
                } header: {
                    Text("Local Network")
                } footer: {
                    Text("When reachable, Hive connects directly to this host instead of the Cloudflare tunnel. Port 8123 (Home Assistant default) is tried first.")
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
                    Button("Done") {
                        saveLanHost()
                        dismiss()
                    }
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
        .onDisappear { saveLanHost() }
    }

    private func saveLanHost() {
        let trimmed = lanHost.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: NetworkResolver.lanHostKey)
        networkResolver.resolve()
    }

    private func maskedString(_ value: String) -> String {
        guard value.count > 8 else { return String(repeating: "\u{2022}", count: value.count) }
        let prefix = String(value.prefix(4))
        let suffix = String(value.suffix(4))
        return "\(prefix)\u{2022}\u{2022}\u{2022}\u{2022}\(suffix)"
    }
}
