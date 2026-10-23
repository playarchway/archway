import Foundation

enum SteamCatalogError: Error, Equatable {
    case notSignedIn
    case network
    case unexpectedResponse

    var message: String {
        switch self {
        case .notSignedIn:
            "Die Steam-Verknüpfung ist abgelaufen. Verknüpfe Steam erneut."
        case .network:
            "Steam ist gerade nicht erreichbar. Prüfe die Internetverbindung und versuche es erneut."
        case .unexpectedResponse:
            "Steam hat unerwartet geantwortet. Versuche es später erneut."
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
}
