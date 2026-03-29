import SwiftUI

struct ContentView: View {
    @EnvironmentObject var config: HiveConfig
    @StateObject private var connectionMonitor = ConnectionMonitor()
    @State private var showSettings = false

    var body: some View {
        Group {
            if config.isConfigured {
                NavigationStack {
                    HiveWebViewContainer(showSettings: $showSettings)
                        .environmentObject(connectionMonitor)
                        .sheet(isPresented: $showSettings) {
                            SettingsView()
                        }
                }
            } else {
                SetupView()
            }
        }
        .ignoresSafeArea()
        .background(Color(red: 0.96, green: 0.94, blue: 0.90))
    }
}
