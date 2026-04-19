import SwiftUI

// MARK: - UIViewControllerRepresentable bridge
//
// HiveWebViewContainer wraps HiveWebViewController (UIKit) in SwiftUI.
// Config and connectivity are passed via updateUIViewController so the VC
// always has current values without polling or combine subscriptions.

struct HiveWebViewContainer: UIViewControllerRepresentable {
    @EnvironmentObject var config: HiveConfig
    @EnvironmentObject var connectionMonitor: ConnectionMonitor
    @Binding var showSettings: Bool

    func makeUIViewController(context: Context) -> HiveWebViewController {
        let vc = HiveWebViewController()
        vc.tunnelURL = config.tunnelURL
        vc.clientId = config.clientId
        vc.clientSecret = config.clientSecret
        vc.isNetworkConnected = connectionMonitor.isConnected
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: HiveWebViewController, context: Context) {
        uiViewController.tunnelURL = config.tunnelURL
        uiViewController.clientId = config.clientId
        uiViewController.clientSecret = config.clientSecret
        uiViewController.isNetworkConnected = connectionMonitor.isConnected
    }

    func makeCoordinator() -> Coordinator { Coordinator(showSettings: $showSettings) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, HiveWebViewControllerDelegate {
        @Binding var showSettings: Bool

        init(showSettings: Binding<Bool>) {
            _showSettings = showSettings
        }

        func hiveWebViewControllerDidRequestSettings(_ controller: HiveWebViewController) {
            showSettings = true
        }
    }
}
