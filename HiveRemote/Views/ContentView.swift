import SwiftUI

struct ContentView: View {
    @EnvironmentObject var config: HiveConfig
    @StateObject private var connectionMonitor = ConnectionMonitor()
    @StateObject private var networkResolver = NetworkResolver()
    @State private var showSettings = false

    var body: some View {
        Group {
            if config.isConfigured {
                NavigationStack {
                    HiveWebViewContainer(showSettings: $showSettings)
                        .environmentObject(connectionMonitor)
                        .environmentObject(networkResolver)
                        .sheet(isPresented: $showSettings) {
                            SettingsView()
                                .environmentObject(networkResolver)
                        }
                }
                .ignoresSafeArea()
                .onAppear {
                    if let url = config.baseURL {
                        networkResolver.start(tunnelURL: url)
                    }
                }
                .onChange(of: config.tunnelURL) { _ in
                    if let url = config.baseURL {
                        networkResolver.start(tunnelURL: url)
                    }
                }
            } else {
                SetupView()
            }
        }
        .background(Color(red: 0.96, green: 0.94, blue: 0.90))
    }
}
