import Foundation
import Combine

final class HiveConfig: ObservableObject {
    private static let tunnelURLKey = "hive_tunnel_url"

    @Published var tunnelURL: String {
        didSet { UserDefaults.standard.set(tunnelURL, forKey: Self.tunnelURLKey) }
    }

    @Published var clientId: String = ""
    @Published var clientSecret: String = ""

    var isConfigured: Bool {
        !tunnelURL.isEmpty && !clientId.isEmpty && !clientSecret.isEmpty
    }

    var baseURL: URL? {
        URL(string: tunnelURL)
    }

    init() {
        self.tunnelURL = UserDefaults.standard.string(forKey: Self.tunnelURLKey) ?? ""
        loadFromKeychain()
    }

    func save() {
        UserDefaults.standard.set(tunnelURL, forKey: Self.tunnelURLKey)
        KeychainService.save(key: "cf_client_id", value: clientId)
        KeychainService.save(key: "cf_client_secret", value: clientSecret)
    }

    func loadFromKeychain() {
        clientId = KeychainService.load(key: "cf_client_id") ?? ""
        clientSecret = KeychainService.load(key: "cf_client_secret") ?? ""
    }

    func clear() {
        tunnelURL = ""
        clientId = ""
        clientSecret = ""
        KeychainService.delete(key: "cf_client_id")
        KeychainService.delete(key: "cf_client_secret")
        UserDefaults.standard.removeObject(forKey: Self.tunnelURLKey)
    }
}
