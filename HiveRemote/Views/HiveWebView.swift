import SwiftUI
import WebKit

// MARK: - WKWebView Representable

struct HiveWebViewRepresentable: UIViewRepresentable {
    let tunnelURL: String
    let onLoadFinished: () -> Void

    @Binding var webView: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.customUserAgent = "HiveRemote/1.0 (iOS; WKWebView)"
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        DispatchQueue.main.async {
            self.webView = webView
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HiveWebViewRepresentable

        init(parent: HiveWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadFinished()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[HiveWebView] Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[HiveWebView] Provisional navigation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Container View

struct HiveWebViewContainer: View {
    @EnvironmentObject var config: HiveConfig
    @EnvironmentObject var connectionMonitor: ConnectionMonitor
    @Binding var showSettings: Bool

    @State private var webView: WKWebView?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            HiveWebViewRepresentable(
                tunnelURL: config.tunnelURL,
                onLoadFinished: { isLoading = false },
                webView: $webView
            )
            .ignoresSafeArea()

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Loading Hive...").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }

            if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48)).foregroundStyle(.orange)
                    Text("Connection Error").font(.title3.bold())
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    Button("Retry") { loadHive() }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }

            if !connectionMonitor.isConnected {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash").font(.title)
                    Text("No Internet Connection").font(.subheadline.bold())
                    Text("Hive will reconnect when you're back online.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .background(Color(red: 0.96, green: 0.94, blue: 0.90)) // Match Hive's warm bg
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                Circle()
                    .fill(connectionMonitor.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Button(action: { loadHive() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.trailing, 16)
            .padding(.bottom, 20)
        }
        .task {
            // Wait for WKWebView to be created by makeUIView
            while webView == nil {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            loadHive()
        }
        .onChange(of: connectionMonitor.isConnected) { _, isConnected in
            if isConnected { loadHive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            loadHive()
        }
    }

    private func loadHive() {
        guard let url = config.baseURL else { return }
        isLoading = true
        errorMessage = nil

        // Just load the URL — tunnel provides security, no auth layer needed
        webView?.load(URLRequest(url: url))
    }
}
