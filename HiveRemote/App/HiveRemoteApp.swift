import SwiftUI

@main
struct HiveRemoteApp: App {
    @StateObject private var config = HiveConfig()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(config)
                .preferredColorScheme(.light)
                .ignoresSafeArea()
                .background(Color(red: 0.96, green: 0.94, blue: 0.90).ignoresSafeArea())
        }
    }
}
