import Foundation
import Observation
import ArchwayCore

/// The library's data: Steam's owned-games list, merged with what is installed in the Archway bottle
/// and with Archway's tested profiles. Keeps the last successful list on disk for offline starts.
@MainActor
@Observable
final class LibraryStore {
    enum Phase: Equatable {
        case needsAccount
        case loading
        case ready
        case failed(SteamCatalogError)
    }

    private(set) var phase: Phase = .loading
    private(set) var steamGames: [LibraryGame] = [] { didSet { sortGames() } }
    private(set) var localGames: [LibraryGame] = [] { didSet { sortGames() } }
    private(set) var lastUpdated: Date?
    /// Every game by title, kept in step with both sources so views don't sort on each render.
    private(set) var games: [LibraryGame] = []

    private func sortGames() {
        games = (steamGames + localGames).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Totals from sessions Archway saw end, until Steam reports them. Steam takes a moment after a session,
    /// and never hears of games that run on the alpha runtime.
    private var sessionTotals: [Int: (minutes: Int, lastPlayedAt: Date)] = [:]
    private var sessionRefresh: Task<Void, Never>?

    private let paths: AppPaths
    private var cacheURL: URL { paths.dataDirectory.appendingPathComponent("steam-library-cache.json") }
    private var localGamesURL: URL { paths.dataDirectory.appendingPathComponent("local-games.json") }
    private var macVersionsURL: URL { paths.dataDirectory.appendingPathComponent("mac-versions.json") }
    /// Which games the store lists with a Mac version, kept on disk and asked again after a week.
    private var macVersions = MacVersions()

    init(paths: AppPaths) {
        self.paths = paths
        if let data = try? Data(contentsOf: macVersionsURL),
           let cached = try? JSONDecoder().decode(MacVersions.self, from: data) { macVersions = cached }
        loadCache()
        loadLocalGames()
    }

    /// Someone has signed in before; the session itself may still have expired.
    var hasAccount: Bool { SteamSession.steamID != nil }

    /// Loads the owned games with the current Steam session. Call after signing in, too.
    func refresh() async {
        // Without a previous link this only checks for a Steam session, so skip the loading state.
        if hasAccount { phase = .loading }
        guard let token = await SteamSession.accessToken(),
              let steamID = SteamSession.steamID(fromToken: token) else {
            phase = hasAccount ? .failed(.notSignedIn) : .needsAccount
            return
        }
        do {
            let owned = try await SteamWebAPI(accessToken: token).ownedGames(steamID: steamID)
            if steamID != SteamSession.steamID { SteamSession.steamID = steamID }
            let steamapps = paths.steamApps
            apply(owned, installed: await Task.detached { Self.installedAppIDs(in: steamapps) }.value, fetchedAt: .now)
            saveCache(owned)
            phase = .ready
            await refreshMacVersions()
        } catch let error as SteamCatalogError {
            phase = .failed(error)
        } catch {
            phase = .failed(.unexpectedResponse)
        }
    }

    func signOut() async {
        await SteamSession.signOut()
        steamGames = []
        lastUpdated = nil
        try? FileManager.default.removeItem(at: cacheURL)
        phase = .needsAccount
    }

    /// Re-reads which Steam games are installed in the bottle, for example while Steam is installing one.
    func refreshInstalled() async {
        let steamapps = paths.steamApps
        let installed = await Task.detached { Self.installedAppIDs(in: steamapps) }.value
        // One assignment, and only on a change, so polling doesn't redraw the library.
        let updated = steamGames.map { game in
            var game = game
            game.isInstalled = installed.contains(game.id)
            return game
        }
        if updated != steamGames { steamGames = updated }
    }

    /// Counts a finished session right away, then asks Steam for its own numbers.
    func recordSession(gameID: Int, from start: Date, to end: Date) {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if let index = steamGames.firstIndex(where: { $0.id == gameID }) {
            sessionTotals[gameID] = (steamGames[index].playtimeMinutes + minutes, end)
            applySessionTotals(to: &steamGames[index])
        } else if let index = localGames.firstIndex(where: { $0.id == gameID }) {
            localGames[index].playtimeMinutes += minutes
            localGames[index].lastPlayedAt = end
            return
        }
        guard hasAccount else { return }
        sessionRefresh?.cancel()
        sessionRefresh = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: Merging

    /// Steam's totals only grow, so the larger value is the newer one.
    private func applySessionTotals(to game: inout LibraryGame) {
        guard let totals = sessionTotals[game.id] else { return }
        game.playtimeMinutes = max(game.playtimeMinutes, totals.minutes)
        game.lastPlayedAt = max(game.lastPlayedAt ?? .distantPast, totals.lastPlayedAt)
    }

    private func apply(_ owned: [SteamWebAPI.OwnedGame], installed: Set<Int>, fetchedAt: Date) {
        steamGames = owned.map { game in
            var entry = LibraryGame(
                id: game.appid,
                title: game.name ?? "App \(game.appid)",
                playtimeMinutes: game.playtimeForever,
                lastPlayedAt: game.rtimeLastPlayed.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil },
                isInstalled: installed.contains(game.appid),
                compatibility: .untested,
                hasMacVersion: macVersions.mac.contains(game.appid))
            applySessionTotals(to: &entry)
            return entry
        }
        lastUpdated = fetchedAt
    }

    /// Steam marks a fully installed game with `StateFlags` 4 in its app manifest.
    nonisolated private static func installedAppIDs(in steamapps: URL) -> Set<Int> {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: steamapps.path) else { return [] }
        var ids = Set<Int>()
        for file in files where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
            guard let id = Int(file.dropFirst("appmanifest_".count).dropLast(".acf".count)),
                  let text = try? String(contentsOf: steamapps.appendingPathComponent(file), encoding: .utf8),
                  let range = text.range(of: #""StateFlags"\s+"(\d+)""#, options: .regularExpression) else { continue }
            let flags = Int(text[range].split(separator: "\"").last ?? "") ?? 0
            if flags & 4 != 0 { ids.insert(id) }
        }
        return ids
    }

    // MARK: Mac versions

    private struct MacVersions: Codable {
        var checkedAt = Date.distantPast
        var checked: Set<Int> = []
        var mac: Set<Int> = []
    }

    /// Asks the store about games it hasn't been asked about, or about all of them once the answers are a week old.
    /// A failure leaves the badges as they were; the next refresh tries again.
    private func refreshMacVersions() async {
        let isStale = macVersions.checkedAt < .now.addingTimeInterval(-7 * 24 * 60 * 60)
        let ids = steamGames.map(\.id).filter { isStale || !macVersions.checked.contains($0) }
        guard !ids.isEmpty else { return }
        var updated = isStale ? MacVersions() : macVersions
        for start in stride(from: 0, to: ids.count, by: 200) {
            let batch = Array(ids[start..<min(start + 200, ids.count)])
            guard let mac = try? await SteamWebAPI.macVersions(of: batch) else { return }
            updated.checked.formUnion(batch)
            updated.mac.formUnion(mac)
        }
        updated.checkedAt = isStale ? .now : macVersions.checkedAt
        macVersions = updated
        try? JSONEncoder().encode(updated).write(to: macVersionsURL, options: .atomic)
        let games = steamGames.map { game in
            var game = game
            game.hasMacVersion = updated.mac.contains(game.id)
            return game
        }
        if games != steamGames { steamGames = games }
    }

    // MARK: Local games

    private struct LocalEntry: Codable {
        let id: Int
        let title: String
        let path: String
    }

    /// Adds a Windows game from a local .exe. It is experimental until someone tests it.
    func addLocalGame(executable url: URL) {
        guard !localGames.contains(where: { $0.executablePath == url.path }) else { return }
        let title = url.deletingPathExtension().lastPathComponent
        // Negative IDs never collide with Steam app IDs.
        let id = -(localGames.map { -$0.id }.max() ?? 0) - 1
        localGames.append(localGame(LocalEntry(id: id, title: title, path: url.path)))
        saveLocalGames()
    }

    func removeLocalGame(_ game: LibraryGame) {
        localGames.removeAll { $0.id == game.id }
        saveLocalGames()
    }

    private func localGame(_ entry: LocalEntry) -> LibraryGame {
        LibraryGame(id: entry.id, title: entry.title, playtimeMinutes: 0, lastPlayedAt: nil,
                    isInstalled: FileManager.default.fileExists(atPath: entry.path),
                    compatibility: .experimental, executablePath: entry.path)
    }

    private func loadLocalGames() {
        guard let data = try? Data(contentsOf: localGamesURL),
              let entries = try? JSONDecoder().decode([LocalEntry].self, from: data) else { return }
        localGames = entries.map(localGame)
    }

    private func saveLocalGames() {
        let entries = localGames.compactMap { game in
            game.executablePath.map { LocalEntry(id: game.id, title: game.title, path: $0) }
        }
        try? FileManager.default.createDirectory(at: localGamesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: localGamesURL, options: .atomic)
    }

    // MARK: Cache

    private struct Cache: Codable {
        let steamID: String
        let fetchedAt: Date
        let games: [SteamWebAPI.OwnedGame]
    }

    private func loadCache() {
        guard let steamID = SteamSession.steamID,
              let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.steamID == steamID else {
            phase = hasAccount ? .loading : .needsAccount
            return
        }
        apply(cache.games, installed: Self.installedAppIDs(in: paths.steamApps), fetchedAt: cache.fetchedAt)
        phase = .ready
    }

    private func saveCache(_ owned: [SteamWebAPI.OwnedGame]) {
        guard let steamID = SteamSession.steamID, let lastUpdated else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Cache(steamID: steamID, fetchedAt: lastUpdated, games: owned))
            .write(to: cacheURL, options: .atomic)
    }
}
