import Foundation

enum SteamCatalogError: Error, Equatable {
    case notSignedIn
    case network
    case unexpectedResponse

    var message: String {
        switch self {
        case .notSignedIn:
            String(localized: "The Steam link has expired. Link Steam again.")
        case .network:
            String(localized: "Steam can’t be reached right now. Check your internet connection and try again.")
        case .unexpectedResponse:
            String(localized: "Steam sent an unexpected response. Try again later.")
        }
    }
}

/// The parts of the Steam Web API the library needs, called with the signed-in session's token.
struct SteamWebAPI {
    struct OwnedGame: Codable, Equatable {
        let appid: Int
        let name: String?
        let playtimeForever: Int
        let rtimeLastPlayed: Int?
    }

    let accessToken: String
    var session: URLSession = .shared

    /// All games the account owns, including free games that have been played.
    func ownedGames(steamID: String) async throws -> [OwnedGame] {
        var components = URLComponents(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/")!
        components.queryItems = [
            .init(name: "access_token", value: accessToken),
            .init(name: "steamid", value: steamID),
            .init(name: "include_appinfo", value: "true"),
            .init(name: "include_played_free_games", value: "true"),
        ]
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch {
            throw SteamCatalogError.network
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw SteamCatalogError.notSignedIn
        default: throw SteamCatalogError.unexpectedResponse
        }

        struct Body: Decodable {
            struct Response: Decodable { let gameCount: Int?; let games: [OwnedGame]? }
            let response: Response
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let body = try? decoder.decode(Body.self, from: data) else { throw SteamCatalogError.unexpectedResponse }
        // The owner's own token sees every game; an empty response means Steam did not accept it.
        guard body.response.gameCount != nil else { throw SteamCatalogError.notSignedIn }
        return body.response.games ?? []
    }

    /// Which of the games the store lists with a macOS version. Public store data, no token needed; Steam answers
    /// for up to a few hundred games at once.
    static func macVersions(of appIDs: [Int], session: URLSession = .shared) async throws -> Set<Int> {
        struct Request: Encodable {
            struct ID: Encodable { let appid: Int }
            struct Context: Encodable { let language = "english"; let countryCode = "US" }
            struct DataRequest: Encodable { let includePlatforms = true }
            let ids: [ID]
            let context = Context()
            let dataRequest = DataRequest()
        }
        struct Body: Decodable {
            struct Response: Decodable { let storeItems: [Item]? }
            struct Item: Decodable { let appid: Int?; let platforms: Platforms? }
            struct Platforms: Decodable { let mac: Bool? }
            let response: Response
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let input = try encoder.encode(Request(ids: appIDs.map(Request.ID.init)))
        var components = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/")!
        components.queryItems = [.init(name: "input_json", value: String(decoding: input, as: UTF8.self))]
        let (data, _) = try await session.data(from: components.url!)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode(Body.self, from: data).response.storeItems ?? []
        return Set(items.compactMap { $0.platforms?.mac == true ? $0.appid : nil })
    }
}
