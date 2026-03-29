import SwiftUI

struct SetupView: View {
    @EnvironmentObject var config: HiveConfig
    @State private var tunnelURL = ""
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var testing = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)

                        Text("Connect to Hive")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("Enter your Cloudflare Tunnel URL and service token credentials to connect to your Hive instance.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Tunnel") {
                    TextField("https://hive.yourdomain.com", text: $tunnelURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Service Token") {
                    TextField("CF-Access-Client-Id", text: $clientId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.username)

                    SecureField("CF-Access-Client-Secret", text: $clientSecret)
                        .textContentType(.password)
                }

                Section {
                    Button(action: testConnection) {
                        HStack {
                            if testing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Text(testing ? "Testing..." : "Test & Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(tunnelURL.isEmpty || clientId.isEmpty || clientSecret.isEmpty || testing)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .listRowBackground(Color.clear)
                }

                if let result = testResult {
                    Section {
                        switch result {
                        case .success:
                            Label("Connection successful", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Setup")
            .onAppear {
                tunnelURL = config.tunnelURL
                clientId = config.clientId
                clientSecret = config.clientSecret
            }
        }
    }

    private func testConnection() {
        testing = true
        testResult = nil

        // Normalize URL: strip trailing slash
        var url = tunnelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url.removeLast() }
        // Add https:// if missing
        if !url.hasPrefix("http") { url = "https://\(url)" }

        Task {
            do {
                try await CloudflareAuth.testConnection(
                    tunnelURL: url,
                    clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
                    clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                await MainActor.run {
                    config.tunnelURL = url
                    config.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
                    config.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                    config.save()
                    testResult = .success
                    testing = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    testing = false
                }
            }
        }
    }
}
