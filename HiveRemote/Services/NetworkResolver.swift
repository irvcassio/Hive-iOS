import Foundation
import Network

enum NetworkMode: Equatable {
    case resolving
    case lan(url: URL)
    case tunnel(url: URL)

    var activeURL: URL? {
        switch self {
        case .resolving: return nil
        case .lan(let url), .tunnel(let url): return url
        }
    }

    var label: String {
        switch self {
        case .resolving: return "..."
        case .lan: return "LAN"
        case .tunnel: return "Cloud"
        }
    }

    var sfSymbol: String {
        switch self {
        case .resolving: return "antenna.radiowaves.left.and.right"
        case .lan: return "wifi"
        case .tunnel: return "cloud"
        }
    }
}

final class NetworkResolver: ObservableObject {
    static let lanHostKey = "hive_lan_host"

    @Published private(set) var mode: NetworkMode = .resolving

    private var tunnelURL: URL?
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.irvcassio.HiveRemote.NetworkResolver", qos: .utility)
    private var resolveTask: Task<Void, Never>?
    private var monitoring = false

    /// Call from main thread when config becomes available or the tunnel URL changes.
    func start(tunnelURL: URL) {
        self.tunnelURL = tunnelURL

        if !monitoring {
            monitoring = true
            pathMonitor.pathUpdateHandler = { [weak self] path in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if path.status == .satisfied {
                        self.resolve()
                    } else {
                        self.mode = .resolving
                    }
                }
            }
            pathMonitor.start(queue: pathQueue)
        }

        resolve()
    }

    /// Re-probe LAN reachability and update mode. Safe to call from main thread.
    func resolve() {
        resolveTask?.cancel()
        resolveTask = Task { await performResolve() }
    }

    private func performResolve() async {
        guard let tunnelURL else { return }

        mode = .resolving
        guard !Task.isCancelled else { return }

        let lanHost = UserDefaults.standard.string(forKey: Self.lanHostKey) ?? "hive.local"

        // Probe all candidates concurrently — first success wins
        let candidates: [URL] = [
            URL(string: "http://\(lanHost):8123"),
            URL(string: "https://\(lanHost):8123"),
            URL(string: "http://\(lanHost)"),
        ].compactMap { $0 }

        let lanURL = await withTaskGroup(of: URL?.self) { group -> URL? in
            for candidate in candidates {
                group.addTask { await self.isReachable(candidate) ? candidate : nil }
            }
            for await result in group {
                if let url = result {
                    group.cancelAll()
                    return url
                }
            }
            return nil
        }

        guard !Task.isCancelled else { return }

        if let lan = lanURL {
            mode = .lan(url: lan)
        } else {
            mode = .tunnel(url: tunnelURL)
        }
    }

    private func isReachable(_ url: URL) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 2.0
        let session = URLSession(configuration: config, delegate: LANSSLBypass(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { $0.statusCode > 0 } ?? false
        } catch {
            return false
        }
    }

    deinit {
        pathMonitor.cancel()
        resolveTask?.cancel()
    }
}

// Accept self-signed TLS during LAN probing — common for local Home Assistant instances
private final class LANSSLBypass: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
