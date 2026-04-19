import UIKit
import WebKit

// MARK: - Delegate

protocol HiveWebViewControllerDelegate: AnyObject {
    func hiveWebViewControllerDidRequestSettings(_ controller: HiveWebViewController)
}

// MARK: - HiveWebViewController

final class HiveWebViewController: UIViewController {

    // MARK: - Configuration (set before/after view loads)

    var tunnelURL: String = ""
    var clientId: String = ""
    var clientSecret: String = ""

    var isNetworkConnected: Bool = true {
        didSet {
            guard isViewLoaded, oldValue != isNetworkConnected else { return }
            updateOfflineOverlay(animated: true)
        }
    }

    weak var delegate: HiveWebViewControllerDelegate?

    // MARK: - Subviews

    private var webView: WKWebView!
    private var loadingOverlay: UIView!
    private var errorOverlay: UIView!
    private var offlineOverlay: UIView!
    private var errorMessageLabel: UILabel!
    private var statusDot: UIView!

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
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Inject safe-area CSS variables and viewport-fit=cover at document
        // start so web content never renders without them, including on
        // hash-routing and history.pushState navigations in SPAs.
        let safeAreaScript = WKUserScript(
            source: """
            (function() {
              var root = document.documentElement;
              root.style.setProperty('--sat', 'env(safe-area-inset-top)');
              root.style.setProperty('--sab', 'env(safe-area-inset-bottom)');
              root.style.setProperty('--sal', 'env(safe-area-inset-left)');
              root.style.setProperty('--sar', 'env(safe-area-inset-right)');
              var meta = document.querySelector('meta[name="viewport"]');
              if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
                document.head && document.head.appendChild(meta);
              } else if (!meta.content.includes('viewport-fit')) {
                meta.content += ', viewport-fit=cover';
              }
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(safeAreaScript)

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        view.addSubview(webView)
        // Full-bleed — safe areas handled via CSS env() injection after load
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
        statusDot = UIView()
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.backgroundColor = .systemGreen
        statusDot.layer.cornerRadius = 4

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

        let row = UIStackView(arrangedSubviews: [statusDot, refreshButton, settingsButton])
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
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            // 44pt minimum touch target per HIG
            refreshButton.widthAnchor.constraint(equalToConstant: 44),
            refreshButton.heightAnchor.constraint(equalToConstant: 44),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44),
            row.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -10),
            // Anchored to safe area so it stays above home indicator on all devices
            capsule.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            capsule.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        // Subtle shadow to ensure visibility against light backgrounds
        capsule.layer.shadowColor = UIColor.black.cgColor
        capsule.layer.shadowOpacity = 0.10
        capsule.layer.shadowRadius = 4
        capsule.layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    // MARK: - Actions

    @objc func loadHive() {
        guard !tunnelURL.isEmpty, let url = URL(string: tunnelURL) else {
            loadingOverlay?.isHidden = true
            return
        }
        loadingOverlay.isHidden = false
        errorOverlay.isHidden = true
        var request = URLRequest(url: url)
        if !clientId.isEmpty && !clientSecret.isEmpty {
            request.setValue(clientId, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        webView.load(request)
    }

    @objc private func settingsTapped() {
        delegate?.hiveWebViewControllerDidRequestSettings(self)
    }

    @objc private func appWillEnterForeground() {
        guard isNetworkConnected else { return }
        loadHive()
    }

    // MARK: - Connectivity

    private func updateOfflineOverlay(animated: Bool) {
        let show = !isNetworkConnected
        statusDot.backgroundColor = isNetworkConnected ? .systemGreen : .systemRed
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
