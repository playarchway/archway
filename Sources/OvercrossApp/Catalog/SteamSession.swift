import Foundation
import WebKit

/// The Steam web session from signing in on Steam's own login page inside Overcross.
/// Overcross never sees the password; it only asks Steam's store for the session's Web API token.
@MainActor
enum SteamSession {
    static let loginURL = URL(string: "https://store.steampowered.com/login/?redir=&redir_ssl=1")!
    static var dataStore: WKWebsiteDataStore { .default() }

    private static let steamIDDefaultsKey = "steamID"

    /// The SteamID of the last successful sign-in, used to match the offline cache.
    static var steamID: String? {
        get { UserDefaults.standard.string(forKey: steamIDDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: steamIDDefaultsKey) }
    }

    /// The signed-in session's Web API token, or nil when nobody is signed in or the session expired.
    static func accessToken() async -> String? {
        let cookies = await cookies(for: "store.steampowered.com")
        guard !cookies.isEmpty else { return nil }

        var request = URLRequest(url: URL(string: "https://store.steampowered.com/pointssummary/ajaxgetasyncconfig")!)
        request.httpShouldHandleCookies = false
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)

        struct Body: Decodable {
            struct Config: Decodable { let webapiToken: String? }
            let success: Int
            let data: Config?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let body = try? decoder.decode(Body.self, from: data),
              body.success == 1,
              let token = body.data?.webapiToken, !token.isEmpty else { return nil }
        return token
    }

    /// The cookies a browser would send to `host`. Steam sets a separate `steamLoginSecure` per subdomain,
    /// and sending another subdomain's copy makes the store treat the request as signed out.
    private static func cookies(for host: String) async -> [HTTPCookie] {
        await dataStore.httpCookieStore.allCookies().filter { cookie in
            cookie.domain == host || (cookie.domain.hasPrefix(".") && host.hasSuffix(cookie.domain))
        }
    }

    /// Steam's token is a JWT whose subject is the SteamID64.
    static func steamID(fromToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = claims["sub"] as? String else { return nil }
        return subject
    }

    /// Removes the Steam session from Overcross' web storage.
    static func signOut() async {
        let records = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let steamRecords = records.filter { $0.displayName.contains("steam") }
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: steamRecords)
        steamID = nil
    }
}
