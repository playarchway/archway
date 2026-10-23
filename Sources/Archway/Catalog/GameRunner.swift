import AppKit
import Observation
import OvercrossCore

/// Starts, watches, and stops games in the Overcross bottle, and follows Steam installs.
/// Wine and Steam work runs off the main thread; the state here drives the play buttons.
@MainActor
@Observable
final class GameRunner {
    enum Activity: Equatable {
        case starting
        case running(since: Date)
        case stopping
        case installing
    }

    /// The Wine build a game starts with.
    enum Runtime: String, CaseIterable, Sendable {
        /// CrossOver-based Wine 11.17 with Steam, the tested default.
        case standard
        /// Archway's own Wine 11.20 build with D3DMetal, in a bottle with its own Windows Steam.
        case archwayAlpha
    }

    private(set) var activities: [Int: Activity] = [:]
    /// Windows Steam runs in the default bottle.
    private(set) var isSteamRunning = false
    private(set) var errors: [Int: String] = [:]

    private let store: LibraryStore
    private var imageNames: [Int: Set<String>] = [:]
    private var startedAt: [Int: Date] = [:]
    private var missedPolls: [Int: Int] = [:]
    /// Games whose window should come to the front once it appears.
    private var pendingFocus: Set<Int> = []
    /// The runtime each started game runs in, so stopping reaches the right bottle.
    private var launchedRuntimes: [Int: Runtime] = [:]
    private(set) var selectedRuntimes: [Int: Runtime] = GameRunner.loadRuntimes()
    private static let runtimesDefaultsKey = "gameRuntimes"
    private var watcher: Task<Void, Never>?
    /// Archway started Steam, so it also closes it once the game is over.
    private var ownsSteam = false
    private var steamShutdown: Task<Void, Never>?

    /// Steam, a first start, and shader caches can take a while before the game window appears.
    private static let startTimeout: TimeInterval = 240

    /// Steam uploads playtime and cloud saves after a game exits; give it time before closing it.
    private static let steamShutdownDelay: Duration = .seconds(15)

    init(store: LibraryStore) {
        self.store = store
        refreshSteamState()
        // Steam keeps running when Archway quits otherwise, and restarts its window when only that is closed.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if self.ownsSteam { try? Self.requestSteamShutdown() } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.refreshSteamState() }
        }
    }

    func activity(for game: LibraryGame) -> Activity? { activities[game.id] }

    func runtime(for game: LibraryGame) -> Runtime { selectedRuntimes[game.id] ?? .standard }

    func setRuntime(_ runtime: Runtime, for game: LibraryGame) {
        selectedRuntimes[game.id] = runtime == .standard ? nil : runtime
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: selectedRuntimes.map { (String($0.key), $0.value.rawValue) }),
                                  forKey: Self.runtimesDefaultsKey)
    }

    /// The alpha runtime only has the games that are installed in its own bottle.
    func isAlphaAvailable(for game: LibraryGame) -> Bool {
        !game.isLocal && (try? Self.orchestrator(.archwayAlpha).steamInstallDirectory(appID: game.id))
            .map { FileManager.default.fileExists(atPath: $0.path) } == true
    }

    private static func loadRuntimes() -> [Int: Runtime] {
        let stored = UserDefaults.standard.dictionary(forKey: runtimesDefaultsKey) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            Int(key).flatMap { id in Runtime(rawValue: value).map { (id, $0) } }
        })
    }

    // MARK: Actions

    func play(_ game: LibraryGame) {
        guard activities[game.id] == nil else { return }
        errors[game.id] = nil
        activities[game.id] = .starting
        startedAt[game.id] = .now
        pendingFocus.insert(game.id)
        let runtime = runtime(for: game)
        launchedRuntimes[game.id] = runtime
        let usesSteam = runtime == .standard && !game.isLocal
        if usesSteam { steamShutdown?.cancel() }
        Task {
            do {
                if usesSteam, await !Task.detached(operation: { Self.steamIsRunning() }).value { ownsSteam = true }
                imageNames[game.id] = try await Task.detached { try Self.launch(game, runtime: runtime) }.value
                watch()
            } catch {
                fail(game, error)
            }
        }
    }

    func stop(_ game: LibraryGame) {
        guard case .running = activities[game.id], let names = imageNames[game.id] else { return }
        activities[game.id] = .stopping
        let runtime = launchedRuntimes[game.id] ?? .standard
        Task {
            do {
                try await Task.detached { try Self.stop(imageNames: names, runtime: runtime) }.value
            } catch {
                fail(game, error)
            }
        }
    }

    func install(_ game: LibraryGame) {
        guard !game.isLocal, activities[game.id] == nil else { return }
        errors[game.id] = nil
        activities[game.id] = .installing
        steamShutdown?.cancel()
        Task {
            do {
                if await !Task.detached(operation: { Self.steamIsRunning() }).value { ownsSteam = true }
                try await Task.detached { try Self.install(appID: game.id) }.value
                watch()
            } catch {
                fail(game, error)
            }
        }
    }

    /// Closes Windows Steam the way its own menu does, so it can finish syncing first.
    func quitSteam() {
        guard canQuitSteam else { return }
        steamShutdown?.cancel()
        steamShutdown = Task { await shutDownSteam() }
    }

    /// Not while a game that needs it runs or installs.
    var canQuitSteam: Bool {
        isSteamRunning && !activities.contains { id, _ in launchedRuntimes[id] != .archwayAlpha && id > 0 }
    }

    private func shutDownSteam() async {
        ownsSteam = false
        try? await Task.detached { try Self.closeSteam() }.value
        refreshSteamState()
    }

    /// After the last game that needed Steam, close it again if Archway started it.
    private func scheduleSteamShutdown() {
        guard ownsSteam else { return }
        steamShutdown?.cancel()
        steamShutdown = Task {
            try? await Task.sleep(for: Self.steamShutdownDelay)
            guard !Task.isCancelled, ownsSteam, canQuitSteam else { return }
            await shutDownSteam()
        }
    }

    private func refreshSteamState() {
        isSteamRunning = Self.steamIsRunning()
    }

    func showFolder(_ game: LibraryGame) {
        if let path = game.executablePath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if let folder = try? Self.orchestrator().steamInstallDirectory(appID: game.id) {
            NSWorkspace.shared.open(folder)
        }
    }

    /// The log of the game's last start, if there is one.
    func logURL(for game: LibraryGame) -> URL? {
        let runtime = runtime(for: game)
        guard let paths = try? Self.paths(runtime) else { return nil }
        let url = paths.logs.appendingPathComponent("\(Self.logLabel(for: game)).log")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Watching

    /// Polls the process list while anything is starting, running, stopping, or installing.
    private func watch() {
        guard watcher == nil else { return }
        watcher = Task {
            while !activities.isEmpty, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await poll()
            }
            watcher = nil
        }
    }

    private func poll() async {
        refreshSteamState()
        if activities.values.contains(.installing) { store.refreshInstalled() }
        for (id, activity) in activities {
            if activity == .installing {
                if store.games.first(where: { $0.id == id })?.isInstalled == true { finish(id) }
                continue
            }
            guard let names = imageNames[id] else { continue }
            let processes = await Task.detached { GameProcesses.running(imageNames: names) }.value
            let isRunning = !processes.isEmpty
            if isRunning, pendingFocus.contains(id) { bringToFront(id, processes) }
            switch activity {
            case .starting where isRunning:
                activities[id] = .running(since: .now)
                startedAt[id] = .now
            case .starting:
                if Date().timeIntervalSince(startedAt[id] ?? .now) > Self.startTimeout {
                    finish(id)
                    errors[id] = String(localized: "The game didn’t start. You’ll find the log under “Advanced”.")
                }
            case .running, .stopping:
                // A game can restart itself (launchers, updates); only treat two misses in a row as an exit.
                missedPolls[id] = isRunning ? 0 : (missedPolls[id] ?? 0) + 1
                if (missedPolls[id] ?? 0) >= 2 {
                    if let since = startedAt[id] { store.recordSession(gameID: id, from: since, to: .now) }
                    let usedSteam = launchedRuntimes[id] == .standard && id > 0
                    finish(id)
                    if usedSteam { scheduleSteamShutdown() }
                }
            case .installing:
                break
            }
        }
    }

    /// Activates the game once its window exists. Only while Archway is in front, so a game that takes
    /// long to start never pulls the player out of another app.
    private func bringToFront(_ id: Int, _ processes: [GameProcesses.Running]) {
        guard NSApp.isActive else { pendingFocus.remove(id); return }
        let apps = processes.compactMap { NSRunningApplication(processIdentifier: $0.pid) }
        guard let app = apps.first(where: { $0.activationPolicy == .regular }) else { return }
        NSApp.yieldActivation(to: app)
        if app.activate() { pendingFocus.remove(id) }
    }

    private func finish(_ id: Int) {
        activities[id] = nil
        pendingFocus.remove(id)
        launchedRuntimes[id] = nil
        missedPolls[id] = nil
        startedAt[id] = nil
    }

    private func fail(_ game: LibraryGame, _ error: Error) {
        finish(game.id)
        errors[game.id] = Self.message(for: error)
    }

    // MARK: Work off the main thread

    nonisolated private static func paths(_ runtime: Runtime) throws -> AppPaths {
        let paths = try AppPaths()
        guard runtime == .archwayAlpha else { return paths }
        return try AppPaths(dataDirectory: paths.dataDirectory.appendingPathComponent("archway-alpha"))
    }

    nonisolated private static func orchestrator(_ runtime: Runtime = .standard) throws -> Orchestrator {
        let paths = try paths(runtime)
        guard let configuration = try ConfigStore(paths: paths).load() else { throw OvercrossError.missingConfiguration }
        return Orchestrator(paths: paths, configuration: configuration)
    }

    /// Matches the label of the request that starts the game; each runtime keeps its logs in its own folder.
    nonisolated private static func logLabel(for game: LibraryGame) -> String {
        game.isLocal ? "local-game-\(-game.id)" : "game-launch-\(game.id)"
    }

    /// Starts the game and returns the image names that identify its processes.
    nonisolated private static func launch(_ game: LibraryGame, runtime: Runtime) throws -> Set<String> {
        if let path = game.executablePath {
            let executable = URL(fileURLWithPath: path)
            try ProcessRunner.startGUIProcess(orchestrator().localGameLaunch(executable: executable, label: logLabel(for: game)))
            return [executable.lastPathComponent.lowercased()]
        }
        let orchestrator = try orchestrator(runtime)
        let folder = orchestrator.steamInstallDirectory(appID: game.id)
        if runtime == .archwayAlpha && folder.map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
            throw RunnerError.notInAlpha
        }
        if game.id == Orchestrator.firstAppID { try orchestrator.prepareD3DMetalGame() }
        let shimActive = try prepareSteam(orchestrator, runtime: runtime)
        try ProcessRunner.sendGUIRequest(orchestrator.gameLaunch(appID: UInt32(game.id), webHelperShim: shimActive))
        return folder.map(GameProcesses.executableNames) ?? []
    }

    /// The standard runtime needs the webhelper shim to draw Steam's window. Archway's Wine draws Chromium's
    /// cross-process windows itself, so the alpha bottle keeps Valve's helper. Returns whether the shim is active.
    nonisolated private static func prepareSteam(_ orchestrator: Orchestrator, runtime: Runtime) throws -> Bool {
        guard runtime == .archwayAlpha else { return try orchestrator.prepareSteam() }
        try orchestrator.removeSteamShim()
        return false
    }

    private enum RunnerError: LocalizedError {
        case notInAlpha
        var errorDescription: String? { String(localized: "The game isn’t installed in the Archway runtime.") }
    }

    /// Asks the game to close, then ends it if it is still there after a few seconds.
    nonisolated private static func stop(imageNames: Set<String>, runtime: Runtime) throws {
        let orchestrator = try orchestrator(runtime)
        for name in imageNames where !GameProcesses.running(imageNames: [name]).isEmpty {
            try ProcessRunner.runSetup(orchestrator.stopRequest(imageName: name, force: false), timeout: 30)
        }
        let deadline = Date().addingTimeInterval(8)
        while !GameProcesses.running(imageNames: imageNames).isEmpty && Date() < deadline { usleep(500_000) }
        for name in imageNames where !GameProcesses.running(imageNames: [name]).isEmpty {
            try? ProcessRunner.runSetup(orchestrator.stopRequest(imageName: name, force: true), timeout: 30)
        }
    }

    nonisolated private static func steamIsRunning() -> Bool {
        (try? orchestrator().wineserverIsRunning()) == true
    }

    nonisolated private static func requestSteamShutdown() throws {
        try ProcessRunner.sendGUIRequest(orchestrator().steamShutdown())
    }

    /// Asks Steam to exit and waits for the bottle's wineserver, like `overcross close-steam`.
    nonisolated private static func closeSteam() throws {
        guard steamIsRunning() else { return }
        let orchestrator = try orchestrator()
        try ProcessRunner.sendGUIRequest(orchestrator.steamShutdown())
        try ProcessRunner.runSetup(orchestrator.wineserverWait(), timeout: 30)
    }

    nonisolated private static func install(appID: Int) throws {
        let orchestrator = try orchestrator()
        let shimActive = try orchestrator.prepareSteam()
        try ProcessRunner.sendGUIRequest(orchestrator.gameInstall(appID: UInt32(appID), webHelperShim: shimActive))
    }

    nonisolated private static func message(for error: Error) -> String {
        switch error as? OvercrossError {
        case .missingConfiguration?: String(localized: "Archway isn’t set up on this Mac yet.")
        case .missingBottle?: String(localized: "Archway’s Windows environment isn’t set up yet.")
        case .missingSteam?: String(localized: "Windows Steam isn’t installed in Archway yet.")
        default: (error as? RunnerError)?.errorDescription ?? String(localized: "That didn’t work: \(error.localizedDescription)")
        }
    }
}
