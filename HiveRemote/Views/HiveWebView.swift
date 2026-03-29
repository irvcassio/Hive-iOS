import SwiftUI
import WebKit

// MARK: - WKWebView Representable

struct HiveWebViewRepresentable: UIViewRepresentable {
    let tunnelURL: String
    let clientId: String
    let clientSecret: String
    let onNavigationToLogin: () -> Void
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
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.customUserAgent = "HiveRemote/1.0 (iOS; WKWebView)"

        DispatchQueue.main.async {
            self.webView = webView
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator (Navigation Delegate)

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HiveWebViewRepresentable
        /// Track whether we've injected auth headers on the initial load
        var hasInjectedAuth = false

        init(parent: HiveWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }

            // Detect redirect to Cloudflare Access login — cookie expired
            let host = url.host ?? ""
            if host.contains("cloudflareaccess.com") || url.path.contains("/cdn-cgi/access/login") {
                parent.onNavigationToLogin()
                return .cancel
            }

            // On the first request to our tunnel, inject service token headers.
            // Cloudflare will validate and return Set-Cookie: CF_Authorization
            // which WKWebView stores natively — no manual cookie injection needed.
            let tunnelHost = URL(string: parent.tunnelURL)?.host ?? ""
            if !hasInjectedAuth && host == tunnelHost {
                let existingHeaders = navigationAction.request.allHTTPHeaderFields ?? [:]
                if existingHeaders["CF-Access-Client-Id"] == nil {
                    hasInjectedAuth = true
                    var request = URLRequest(url: url)
                    request.setValue(parent.clientId, forHTTPHeaderField: "CF-Access-Client-Id")
                    request.setValue(parent.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
                    webView.load(request)
                    return .cancel
                }
            }

            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadFinished()

            let keepaliveJS = """
            (function() {
                if (!window.__hiveKeepalive) {
                    window.__hiveKeepalive = setInterval(function() {}, 30000);
                }
            })();
            """
            webView.evaluateJavaScript(keepaliveJS, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[HiveWebView] Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[HiveWebView] Provisional navigation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Container View with Auth + Status

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
                clientId: config.clientId,
                clientSecret: config.clientSecret,
                onNavigationToLogin: handleCookieExpiry,
                onLoadFinished: { isLoading = false },
                webView: $webView
            )
            .ignoresSafeArea(edges: .bottom)

            if isLoading {
                loadingOverlay
            }

            if let error = errorMessage {
                errorOverlay(error)
            }

            if !connectionMonitor.isConnected {
                offlineOverlay
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionMonitor.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text("Hive")
                        .font(.headline)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHive()
        }
        .onChange(of: connectionMonitor.isConnected) { _, isConnected in
            if isConnected && errorMessage != nil {
                Task { await loadHive() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await loadHive() }
        }
    }

    // MARK: - Overlays

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading Hive...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Connection Error")
                .font(.title3.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Retry") {
                Task { await loadHive() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var offlineOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.title)
            Text("No Internet Connection")
                .font(.subheadline.bold())
            Text("Hive will reconnect when you're back online.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Loading

    private func loadHive() async {
        guard config.isConfigured, let url = config.baseURL else { return }

        isLoading = true
        errorMessage = nil

        // Wait for WebView to be ready
        if webView == nil {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        guard let wv = webView else {
            errorMessage = "WebView failed to initialize"
            isLoading = false
            return
        }

        // Reset the coordinator's auth flag so headers get injected
        if let coordinator = (wv.navigationDelegate as? HiveWebViewRepresentable.Coordinator) {
            coordinator.hasInjectedAuth = false
        }

        // Just load the URL — the navigation delegate will intercept
        // the first request and add service token headers automatically.
        // Cloudflare returns Set-Cookie: CF_Authorization in the response,
        // which WKWebView stores natively for all subsequent requests.
        await MainActor.run {
            wv.load(URLRequest(url: url))
        }
    }

    private func handleCookieExpiry() {
        Task { await loadHive() }
    }

    private func reload() {
        Task { await loadHive() }
    }
}
