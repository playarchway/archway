import Foundation

/// Public store data for one Steam app (no API key needed), in German.
struct SteamStoreDetails: Decodable {
    struct ReleaseDate: Decodable { let date: String }
    struct Item: Decodable { let description: String }
    struct Achievements: Decodable { let total: Int }
    struct Screenshot: Decodable, Identifiable {
        let id: Int
        let pathThumbnail: URL
        let pathFull: URL
    }

    let shortDescription: String
    let developers: [String]?
    let publishers: [String]?
    let releaseDate: ReleaseDate?
    let genres: [Item]?
    let categories: [Item]?
    let screenshots: [Screenshot]?
    let backgroundRaw: URL?
    let achievements: Achievements?
    let controllerSupport: String?

    var summary: String {
        shortDescription
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    var features: [String] { categories?.map(\.description) ?? [] }
    var hasCloudSaves: Bool { features.contains("Steam Cloud") }
}

/// Loads and caches store details for the session.
@MainActor
final class SteamStoreClient {
    static let shared = SteamStoreClient()

    private var cache: [Int: SteamStoreDetails] = [:]

    func details(for appID: Int) async throws -> SteamStoreDetails {
        if let cached = cache[appID] { return cached }
        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        components.queryItems = [.init(name: "appids", value: String(appID)),
                                 .init(name: "l", value: "german"),
                                 .init(name: "cc", value: "de")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)

        struct Envelope: Decodable { let success: Bool; let data: SteamStoreDetails? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let details = try decoder.decode([String: Envelope].self, from: data)[String(appID)]?.data else {
            throw URLError(.cannotParseResponse)
        }
        cache[appID] = details
        return details
    }
}
