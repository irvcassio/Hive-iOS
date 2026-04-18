import SwiftUI
import WebKit

// MARK: - WKWebView Representable
//
// Cloudflare Access auth strategy
// --------------------------------
// The tunnel hostname is protected by a Cloudflare Access application with a
// service-token policy. The iOS app must prove it holds the service token to
// pass the edge.
//
// We intentionally do NOT inject CF_Authorization cookies manually into
// `WKWebsiteDataStore` — WebKit has a long-standing timing bug where a cookie
// set via `setCookie` or `document.cookie` is not included on the very next
// navigation. Prior attempts (cookie injection, loadHTMLString tricks) were
// unreliable on both iOS and Android WebViews.
//
// Instead, `decidePolicyFor navigationAction`:
//   1. Sees the first request to the tunnel host with no Access cookie.
//   2. Cancels it and re-issues the same URL with CF-Access-Client-Id and
//      CF-Access-Client-Secret headers set on the `URLRequest`.
//   3. Cloudflare Access validates the headers and returns
//      `Set-Cookie: CF_Authorization=...`.
//   4. WKWebView stores the cookie via its normal Set-Cookie path — no manual
//      cookie store writes — and uses it for every subresource and later
//      navigation automatically.
//
// If the cookie expires later, Access redirects to cloudflareaccess.com /
// `/cdn-cgi/access/login`. We detect that redirect, cancel, and re-inject
// headers so auth is transparent.

struct HiveWebViewRepresentable: UIViewRepresentable {
    let tunnelURL: String
    let clientId: String
    let clientSecret: String
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

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }

            let host = url.host ?? ""
            let tunnelHost = URL(string: parent.tunnelURL)?.host ?? ""

            // Access login bounce (cookie expired or missing) — re-auth by
            // re-loading the tunnel URL with service-token headers.
            if host.contains("cloudflareaccess.com") || url.path.contains("/cdn-cgi/access/login") {
                if let tunnel = URL(string: parent.tunnelURL) {
                    var retry = URLRequest(url: tunnel)
                    retry.setValue(parent.clientId, forHTTPHeaderField: "CF-Access-Client-Id")
                    retry.setValue(parent.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
                    webView.load(retry)
                }
                return .cancel
            }

            // First hit to the tunnel host without our headers — cancel and
            // re-issue with the service token so Access returns CF_Authorization.
            if host == tunnelHost {
                let existing = navigationAction.request.allHTTPHeaderFields ?? [:]
                if existing["CF-Access-Client-Id"] == nil {
                    var signed = URLRequest(url: url)
                    signed.httpMethod = navigationAction.request.httpMethod ?? "GET"
                    signed.setValue(parent.clientId, forHTTPHeaderField: "CF-Access-Client-Id")
                    signed.setValue(parent.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
                    webView.load(signed)
                    return .cancel
                }
            }

            return .allow
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
                clientId: config.clientId,
                clientSecret: config.clientSecret,
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
        guard let url = config.baseURL, let webView else { return }
        isLoading = true
        errorMessage = nil
        // Send service-token headers on the very first navigation.
        // Cloudflare Access returns CF_Authorization in Set-Cookie and
        // WKWebView reuses it for every subresource. See header comment.
        var request = URLRequest(url: url)
        if !config.clientId.isEmpty && !config.clientSecret.isEmpty {
            request.setValue(config.clientId, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(config.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        webView.load(request)
    }
}
