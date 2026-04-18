import Foundation

enum AuthError: LocalizedError {
    case invalidURL
    case noResponse
    case unauthorized(Int)
    case accessNotEnforced
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid tunnel URL"
        case .noResponse: return "No response from server"
        case .unauthorized(let code): return "Authentication failed (HTTP \(code))"
        case .accessNotEnforced:
            return "Tunnel responds without a service token — Cloudflare Access is NOT enforced on this hostname. Add an Access application + service-token policy before using the app."
        case .networkError(let error): return error.localizedDescription
        }
    }
}

final class CloudflareAuth {

    /// Validate tunnel credentials for setup. Performs TWO probes:
    ///
    /// 1. **Unauthed probe** — GET the tunnel with no headers, redirects disabled.
    ///    Cloudflare Access MUST reject this: a 302 to cloudflareaccess.com
    ///    / /cdn-cgi/access/login, or 401/403. Anything in 2xx means the
    ///    hostname has no Access policy and the service token is useless —
    ///    we fail setup with `.accessNotEnforced` rather than silently
    ///    accepting a naked tunnel.
    ///
    /// 2. **Authed probe** — GET with service-token headers, redirects allowed.
    ///    Must land on a 2xx. A 401/403 here means the token is wrong.
    ///
    /// This replaces the prior single-GET test which returned success whether
    /// or not Access was actually enforced.
    static func testConnection(
        tunnelURL: String,
        clientId: String,
        clientSecret: String
    ) async throws {
        guard let url = URL(string: tunnelURL) else {
            throw AuthError.invalidURL
        }

        try await probeAccessEnforced(url: url)
        try await probeAuthedRequestSucceeds(url: url, clientId: clientId, clientSecret: clientSecret)
    }

    private static func probeAccessEnforced(url: URL) async throws {
        let config = URLSessionConfiguration.ephemeral
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.noResponse
        }

        // 302/303/307 to Access login, or 401/403 = Access enforced. Good.
        if (300...399).contains(http.statusCode) || http.statusCode == 401 || http.statusCode == 403 {
            return
        }

        // 2xx without auth = tunnel is wide open. This is the exact bug
        // this test exists to catch: a service token stored to Keychain
        // while the tunnel hostname has no Access policy.
        if (200...299).contains(http.statusCode) {
            throw AuthError.accessNotEnforced
        }

        throw AuthError.unauthorized(http.statusCode)
    }

    private static func probeAuthedRequestSucceeds(
        url: URL,
        clientId: String,
        clientSecret: String
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(clientId, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        request.timeoutInterval = 15

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.noResponse
        }

        guard (200...399).contains(http.statusCode) else {
            throw AuthError.unauthorized(http.statusCode)
        }
    }
}

/// URLSession delegate that disables automatic redirect following so we can
/// observe whether Cloudflare Access bounces an unauthenticated request.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
