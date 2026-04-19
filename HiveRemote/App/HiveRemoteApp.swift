import SwiftUI

@main
struct HiveRemoteApp: App {
    @StateObject private var config = HiveConfig()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(config)
                .preferredColorScheme(.light)
        }
    }
}
