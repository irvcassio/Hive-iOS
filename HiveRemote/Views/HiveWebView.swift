import SwiftUI

// MARK: - UIViewControllerRepresentable bridge
//
// HiveWebViewContainer wraps HiveWebViewController (UIKit) in SwiftUI.
// Config, connectivity, and network mode are passed via updateUIViewController
// so the VC always has current values without polling or Combine subscriptions.
// NetworkResolver.mode changes trigger updateUIViewController via @EnvironmentObject
// observation, which propagates the resolved URL to the VC.

struct HiveWebViewContainer: UIViewControllerRepresentable {
    @EnvironmentObject var config: HiveConfig
    @EnvironmentObject var connectionMonitor: ConnectionMonitor
    @EnvironmentObject var networkResolver: NetworkResolver
    @Binding var showSettings: Bool

    func makeUIViewController(context: Context) -> HiveWebViewController {
        let vc = HiveWebViewController()
        vc.tunnelURL = config.tunnelURL
        vc.clientId = config.clientId
        vc.clientSecret = config.clientSecret
        vc.isNetworkConnected = connectionMonitor.isConnected
        vc.networkMode = networkResolver.mode
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: HiveWebViewController, context: Context) {
        uiViewController.tunnelURL = config.tunnelURL
        uiViewController.clientId = config.clientId
        uiViewController.clientSecret = config.clientSecret
        uiViewController.isNetworkConnected = connectionMonitor.isConnected
        uiViewController.networkMode = networkResolver.mode
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
