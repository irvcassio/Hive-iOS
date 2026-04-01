import Foundation
import WebKit

enum AuthError: LocalizedError {
    case invalidURL
    case noResponse
    case unauthorized(Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid tunnel URL"
        case .noResponse: return "No response from server"
        case .unauthorized(let code): return "Authentication failed (HTTP \(code))"
        case .networkError(let error): return error.localizedDescription
        }
    }
}

final class CloudflareAuth {

    /// Test authentication with Cloudflare Access using service token headers.
    /// Returns true if the tunnel URL accepts the token (HTTP 200-399).
    /// Used by SetupView to validate credentials before saving.
    static func testConnection(
        tunnelURL: String,
        clientId: String,
        clientSecret: String
    ) async throws {
        guard let url = URL(string: tunnelURL) else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(clientId, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        request.timeoutInterval = 15

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.noResponse
        }

        guard (200...399).contains(httpResponse.statusCode) else {
            throw AuthError.unauthorized(httpResponse.statusCode)
        }
    }

    /// Authenticate with Cloudflare Access and return the CF_Authorization cookie.
    /// The WebView needs this cookie to pass through Cloudflare Access on every request.
    static func fetchAuthCookie(
        tunnelURL: String,
        clientId: String,
        clientSecret: String
    ) async throws -> [HTTPCookie] {
        guard let url = URL(string: tunnelURL) else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(clientId, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        request.timeoutInterval = 15

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.noResponse
        }

        guard (200...399).contains(httpResponse.statusCode) else {
            throw AuthError.unauthorized(httpResponse.statusCode)
        }

        // Extract Set-Cookie headers → HTTPCookie objects
        let headerFields = httpResponse.allHeaderFields as? [String: String] ?? [:]
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        return cookies
    }

    /// Inject cookies into a WKWebView's cookie store.
    static func injectCookies(_ cookies: [HTTPCookie], into webView: WKWebView) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in cookies {
            await store.setCookie(cookie)
        }
    }
}
