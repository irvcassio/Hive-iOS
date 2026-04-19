import UIKit
import WebKit

// MARK: - Delegate

protocol HiveWebViewControllerDelegate: AnyObject {
    func hiveWebViewControllerDidRequestSettings(_ controller: HiveWebViewController)
}

// MARK: - HiveWebViewController

final class HiveWebViewController: UIViewController {

    // MARK: - Configuration (set by SwiftUI bridge via updateUIViewController)

    var tunnelURL: String = ""
    var clientId: String = ""
    var clientSecret: String = ""

    var isNetworkConnected: Bool = true {
        didSet {
            guard isViewLoaded, oldValue != isNetworkConnected else { return }
            updateOfflineOverlay(animated: true)
        }
    }

    /// Updated by the SwiftUI bridge whenever NetworkResolver resolves a new path.
    var networkMode: NetworkMode = .resolving {
        didSet {
            guard isViewLoaded, oldValue != networkMode else { return }
            handleNetworkModeChange()
        }
    }

    weak var delegate: HiveWebViewControllerDelegate?

    // MARK: - Subviews

    private var webView: WKWebView!
    private var loadingOverlay: UIView!
    private var errorOverlay: UIView!
    private var offlineOverlay: UIView!
    private var errorMessageLabel: UILabel!
    private var networkBadgeImageView: UIImageView!
    private var networkBadgeLabel: UILabel!

    // MARK: - State

    private var hasLoaded = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)
        setupWebView()
        setupLoadingOverlay()
        setupErrorOverlay()
        setupOfflineOverlay()
        setupControlCapsule()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasLoaded {
            hasLoaded = true
            loadHive()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // .default() is the persistent store — CF_Authorization cookies survive
        // app backgrounding, relaunches, and foreground/background cycles.
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Build viewport content at compile time.
        // To allow user pinch-to-zoom, add ENABLE_PINCH_TO_ZOOM to
        // Build Settings → Swift Compiler – Custom Flags → Active Compilation Conditions.
        #if ENABLE_PINCH_TO_ZOOM
        let viewportContent = "width=device-width, initial-scale=1, viewport-fit=cover"
        #else
        let viewportContent = "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover"
        #endif

        // Injected at document start so it runs before any web-app JS, including
        // on hash-routing and history.pushState navigations in SPAs.
        let setupScript = WKUserScript(
            source: """
            (function() {
              var root = document.documentElement;

              // Safe-area CSS custom properties — consumed by web-app layout
              root.style.setProperty('--sat', 'env(safe-area-inset-top)');
              root.style.setProperty('--sab', 'env(safe-area-inset-bottom)');
              root.style.setProperty('--sal', 'env(safe-area-inset-left)');
              root.style.setProperty('--sar', 'env(safe-area-inset-right)');

              // Prevent horizontal overflow on narrow viewports (375pt iPhone SE).
              // Eliminates horizontal scroll without touching the web app's layout.
              root.style.maxWidth = '100vw';
              root.style.overflowX = 'hidden';
              if (document.body) document.body.style.overflowX = 'hidden';

              // Viewport meta: inject if absent; otherwise patch only viewport-fit
              // so we don't override the web app's own scaling preferences.
              var meta = document.querySelector('meta[name="viewport"]');
              if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = '\(viewportContent)';
                if (document.head) document.head.appendChild(meta);
              } else if (!meta.content.includes('viewport-fit')) {
                meta.content += ', viewport-fit=cover';
              }
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(setupScript)

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // bounces = false disables both scroll bounce and pull-to-refresh.
        // If a UIRefreshControl is added later, set alwaysBounceVertical = true.
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Hide native scroll indicators; avoids double-scrollbar appearance on iPad
        // when web content also renders its own scroll UI.
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Pinch-to-zoom disabled by default — web app controls its own scaling.
        // Toggle via ENABLE_PINCH_TO_ZOOM in Active Compilation Conditions.
        #if !ENABLE_PINCH_TO_ZOOM
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        #endif

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        view.addSubview(webView)
        // Full-bleed — safe areas communicated to web content via CSS env() vars above
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: - Loading Overlay

    private func setupLoadingOverlay() {
        loadingOverlay = UIView()
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.backgroundColor = UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Loading Hive…"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16

        loadingOverlay.addSubview(blurView)
        loadingOverlay.addSubview(stack)
        view.addSubview(loadingOverlay)

        NSLayoutConstraint.activate([
            loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: loadingOverlay.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: loadingOverlay.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: loadingOverlay.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: loadingOverlay.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
        ])
    }

    // MARK: - Error Overlay

    private func setupErrorOverlay() {
        errorOverlay = UIView()
        errorOverlay.translatesAutoresizingMaskIntoConstraints = false
        errorOverlay.isHidden = true

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .systemOrange
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Connection Error"
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center

        errorMessageLabel = UILabel()
        errorMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        errorMessageLabel.font = .preferredFont(forTextStyle: .subheadline)
        errorMessageLabel.textColor = .secondaryLabel
        errorMessageLabel.textAlignment = .center
        errorMessageLabel.numberOfLines = 0

        var retryConfig = UIButton.Configuration.filled()
        retryConfig.title = "Retry"
        retryConfig.baseForegroundColor = .white
        retryConfig.baseBackgroundColor = .systemOrange
        retryConfig.cornerStyle = .medium
        let retryButton = UIButton(configuration: retryConfig)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(loadHive), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, errorMessageLabel, retryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16

        errorOverlay.addSubview(blurView)
        errorOverlay.addSubview(stack)
        view.addSubview(errorOverlay)

        NSLayoutConstraint.activate([
            errorOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            errorOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            errorOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: errorOverlay.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: errorOverlay.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: errorOverlay.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: errorOverlay.trailingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
            stack.centerXAnchor.constraint(equalTo: errorOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorOverlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: errorOverlay.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: errorOverlay.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Offline Overlay

    private func setupOfflineOverlay() {
        offlineOverlay = UIView()
        offlineOverlay.translatesAutoresizingMaskIntoConstraints = false
        offlineOverlay.isHidden = true

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "wifi.slash"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "No Internet Connection"
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center

        let subLabel = UILabel()
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.text = "Hive will reconnect when you're back online."
        subLabel.font = .preferredFont(forTextStyle: .caption1)
        subLabel.textColor = .secondaryLabel
        subLabel.textAlignment = .center
        subLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8

        offlineOverlay.addSubview(blurView)
        offlineOverlay.addSubview(stack)
        view.addSubview(offlineOverlay)

        NSLayoutConstraint.activate([
            offlineOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            offlineOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            offlineOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            offlineOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: offlineOverlay.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: offlineOverlay.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: offlineOverlay.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: offlineOverlay.trailingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            stack.centerXAnchor.constraint(equalTo: offlineOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: offlineOverlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: offlineOverlay.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: offlineOverlay.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Control Capsule

    private func setupControlCapsule() {
        // Network mode badge: shows LAN / Cloud / resolving
        networkBadgeImageView = UIImageView()
        networkBadgeImageView.translatesAutoresizingMaskIntoConstraints = false
        networkBadgeImageView.contentMode = .scaleAspectFit

        networkBadgeLabel = UILabel()
        networkBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        networkBadgeLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)

        let badgeStack = UIStackView(arrangedSubviews: [networkBadgeImageView, networkBadgeLabel])
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        badgeStack.axis = .horizontal
        badgeStack.alignment = .center
        badgeStack.spacing = 3

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        let refreshButton = UIButton(type: .system)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: symbolConfig), for: .normal)
        refreshButton.tintColor = .label
        refreshButton.accessibilityLabel = "Reload"
        refreshButton.addTarget(self, action: #selector(loadHive), for: .touchUpInside)

        let settingsButton = UIButton(type: .system)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.setImage(UIImage(systemName: "gearshape", withConfiguration: symbolConfig), for: .normal)
        settingsButton.tintColor = .label
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [badgeStack, refreshButton, settingsButton])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12

        let capsule = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.layer.cornerRadius = 20
        capsule.layer.masksToBounds = true
        capsule.contentView.addSubview(row)

        view.addSubview(capsule)

        NSLayoutConstraint.activate([
            networkBadgeImageView.widthAnchor.constraint(equalToConstant: 11),
            networkBadgeImageView.heightAnchor.constraint(equalToConstant: 11),
            row.topAnchor.constraint(equalTo: capsule.contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -14),
            // Anchored to safe area so it stays above home indicator on all devices
            capsule.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            capsule.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        updateNetworkBadge()
    }

    // MARK: - Network Badge

    private func updateNetworkBadge() {
        let symbolName: String
        let label: String
        let color: UIColor

        switch networkMode {
        case .resolving:
            symbolName = "antenna.radiowaves.left.and.right"
            label = "..."
            color = .secondaryLabel
        case .lan:
            symbolName = "wifi"
            label = "LAN"
            color = .systemGreen
        case .tunnel:
            symbolName = "cloud"
            label = "Cloud"
            color = .systemBlue
        }

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        networkBadgeImageView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)
        networkBadgeImageView.tintColor = color
        networkBadgeLabel.text = label
        networkBadgeLabel.textColor = color
    }

    // MARK: - Network Mode Handling

    private func handleNetworkModeChange() {
        updateNetworkBadge()

        switch networkMode {
        case .resolving:
            // Only show full-screen spinner on initial load; mid-session re-probes keep WebView visible
            if !hasLoaded { loadingOverlay.isHidden = false }
            errorOverlay.isHidden = true
        case .lan(let url):
            if webView.url?.host != url.host {
                loadHive()
            }
        case .tunnel(let url):
            if webView.url?.host != url.host {
                loadHive()
            }
        }
    }
    // MARK: - Actions

    @objc func loadHive() {
        guard isViewLoaded else { return }

        switch networkMode {
        case .resolving:
            loadingOverlay.isHidden = false
            errorOverlay.isHidden = true

        case .lan(let url):
            loadingOverlay.isHidden = false
            errorOverlay.isHidden = true
            webView.load(URLRequest(url: url))

        case .tunnel(let url):
            loadingOverlay.isHidden = false
            errorOverlay.isHidden = true
            var request = URLRequest(url: url)
            if !clientId.isEmpty && !clientSecret.isEmpty {
                request.setValue(clientId, forHTTPHeaderField: "CF-Access-Client-Id")
                request.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
            }
            webView.load(request)
        }
    }
    @objc private func settingsTapped() {
        delegate?.hiveWebViewControllerDidRequestSettings(self)
    }

    @objc private func appWillEnterForeground() {
        // loadHive() will be triggered via handleNetworkModeChange when NetworkResolver settles.
    }

    // MARK: - Connectivity

    private func updateOfflineOverlay(animated: Bool) {
        let show = !isNetworkConnected
        // NetworkResolver re-probes and calls handleNetworkModeChange → loadHive when connectivity is restored.
        if animated {
            UIView.animate(withDuration: 0.3) {
                self.offlineOverlay.alpha = show ? 1 : 0
            } completion: { _ in
                self.offlineOverlay.isHidden = !show
                self.offlineOverlay.alpha = 1
                // Defer reload until after fade-out so overlays don't collide
                if !show { self.loadHive() }
            }
        } else {
            offlineOverlay.isHidden = !show
            if !show { loadHive() }
        }
    }

    // Safe-area CSS injection is done via WKUserScript at documentStart (see
    // setupWebView). No post-load re-injection needed.
}

// MARK: - WKNavigationDelegate

extension HiveWebViewController: WKNavigationDelegate {

    // Accept self-signed TLS on LAN hosts (common for local Home Assistant instances)
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              isLocalHost(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        let host = url.host ?? ""
        let tunnelHost = URL(string: tunnelURL)?.host ?? ""

        // CF Access login bounce (cookie expired) — re-auth transparently
        if host.contains("cloudflareaccess.com") || url.path.contains("/cdn-cgi/access/login") {
            if let tunnel = URL(string: tunnelURL) {
                var retry = URLRequest(url: tunnel)
                retry.setValue(clientId, forHTTPHeaderField: "CF-Access-Client-Id")
                retry.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
                webView.load(retry)
            }
            return .cancel
        }

        // First hit to tunnel host without service-token headers — inject them
        if host == tunnelHost {
            let existing = navigationAction.request.allHTTPHeaderFields ?? [:]
            if existing["CF-Access-Client-Id"] == nil {
                var signed = URLRequest(url: url)
                signed.httpMethod = navigationAction.request.httpMethod ?? "GET"
                signed.setValue(clientId, forHTTPHeaderField: "CF-Access-Client-Id")
                signed.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
                webView.load(signed)
                return .cancel
            }
        }

        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingOverlay.isHidden = true
        errorOverlay.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        // NSURLErrorCancelled is the cancel-and-retry signal from our CF auth logic
        guard nsError.code != NSURLErrorCancelled else { return }
        showError(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        showError(error.localizedDescription)
    }

    private func showError(_ message: String) {
        loadingOverlay.isHidden = true
        errorOverlay.isHidden = false
        errorMessageLabel.text = message
    }

    private func isLocalHost(_ host: String) -> Bool {
        if host.hasSuffix(".local") || host == "localhost" { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10
            || octets[0] == 127
            || (octets[0] == 169 && octets[1] == 254)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }
}

// MARK: - WKUIDelegate (native JS dialogs)

extension HiveWebViewController: WKUIDelegate {

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}
