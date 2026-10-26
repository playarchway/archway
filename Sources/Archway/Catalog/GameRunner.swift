import AppKit
import Observation
import ArchwayCore

/// Starts, watches, and stops games in the Archway bottle, and follows Steam installs.
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

    private(set) var activities: [Int: Activity] = [:]
    /// Windows Steam runs in the default bottle.
    private(set) var isSteamRunning = false
    private(set) var errors: [Int: String] = [:]
    /// Download progress of installing games, from 0 to 1, once Steam has sized the download.
    private(set) var installProgress: [Int: Double] = [:]
    /// What Steam is doing for each installing game, once it has picked the game up.
    private(set) var installPhases: [Int: Orchestrator.SteamInstallPhase] = [:]
    /// Games that wait for Windows Steam: for its sign-in, or for a running game to end before Steam restarts.
    private(set) var installNotes: [Int: InstallNote] = [:]
    private(set) var uninstalling: Set<Int> = []
    private(set) var completedSession: CompletedGameSession?
    private(set) var lastObservedSessions: [Int: CompletedGameSession] = [:]

    struct CompletedGameSession: Identifiable {
        let id = UUID()
        let game: LibraryGame
        let context: CompatibilityContext
    }

    enum InstallNote: Equatable {
        case signIn
        case waitsForGame
    }

    private let store: LibraryStore
    private let compatibility: CompatibilityStore
    private var imageNames: [Int: Set<String>] = [:]
    private var startedAt: [Int: Date] = [:]
    private var missedPolls: [Int: Int] = [:]
    private var manuallyStopped: Set<Int> = []
    private var launchContexts: [Int: CompatibilityContext] = [:]
    /// Games whose window should come to the front once it appears.
    private var pendingFocus: Set<Int> = []
    private var watcher: Task<Void, Never>?
    /// Archway started Steam, so it also closes it once the game is over.
    private var ownsSteam = false
    private var steamShutdown: Task<Void, Never>?

    /// Steam, a first start, and shader caches can take a while before the game window appears.
    private static let startTimeout: TimeInterval = 240

    /// Steam uploads playtime and cloud saves after a game exits; give it time before closing it.
    private static let steamShutdownDelay: Duration = .seconds(15)

    init(store: LibraryStore, compatibility: CompatibilityStore) {
        self.store = store
        self.compatibility = compatibility
        // Games could once pick a separate alpha runtime; there is only one now.
        UserDefaults.standard.removeObject(forKey: "gameRuntimes")
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

    // MARK: Actions

    func play(_ game: LibraryGame) {
        guard activities[game.id] == nil else { return }
        errors[game.id] = nil
        activities[game.id] = .starting
        startedAt[game.id] = .now
        let profile = compatibility.profile(for: game.id)
        launchContexts[game.id] = compatibility.context(for: game.id, profile: profile)
        pendingFocus.insert(game.id)
        let usesSteam = !game.isLocal
        if usesSteam { steamShutdown?.cancel() }
        Task {
            do {
                if usesSteam, await !Task.detached(operation: { Self.steamIsRunning() }).value { ownsSteam = true }
                imageNames[game.id] = try await Task.detached { try Self.launch(game, profile: profile) }.value
                watch()
            } catch {
                fail(game, error)
            }
        }
    }

    func stop(_ game: LibraryGame) {
        guard case .running = activities[game.id], let names = imageNames[game.id] else { return }
        activities[game.id] = .stopping
        manuallyStopped.insert(game.id)
        Task {
            do {
                try await Task.detached { try Self.stop(imageNames: names) }.value
            } catch {
                fail(game, error)
            }
        }
    }

    /// Queues the game for Steam and lets Steam download it in the background, without its window.
    /// Steam reads new downloads when it starts, so a running Steam restarts, unless a game needs it.
    func install(_ game: LibraryGame) {
        guard !game.isLocal, activities[game.id] == nil else { return }
        errors[game.id] = nil
        activities[game.id] = .installing
        steamShutdown?.cancel()
        let gameNeedsSteam = steamGameIsActive
        Task {
            do {
                let wasRunning = await Task.detached(operation: { Self.steamIsRunning() }).value
                if !wasRunning { ownsSteam = true }
                let signedIn = try await Task.detached {
                    try Self.queueInstall(appID: game.id, name: game.title, restartSteam: wasRunning && !gameNeedsSteam)
                }.value
                if !signedIn { installNotes[game.id] = .signIn }
                if wasRunning && gameNeedsSteam { installNotes[game.id] = .waitsForGame }
                watch()
            } catch {
                fail(game, error)
            }
        }
    }

    /// Removes the game from the bottle. Steam closes first, so it doesn't restore what is being deleted.
    func uninstall(_ game: LibraryGame) {
        guard !game.isLocal, activities[game.id] == nil, !uninstalling.contains(game.id), !steamGameIsActive else { return }
        errors[game.id] = nil
        uninstalling.insert(game.id)
        steamShutdown?.cancel()
        Task {
            do {
                try await Task.detached {
                    try Self.closeSteam()
                    try Self.orchestrator().uninstallSteamGame(appID: game.id)
                }.value
                ownsSteam = false
            } catch {
                errors[game.id] = Self.message(for: error)
            }
            uninstalling.remove(game.id)
            refreshSteamState()
            store.refreshInstalled()
        }
    }

    /// Uninstalling closes Steam, which would end a game that runs through it.
    var canUninstall: Bool { !steamGameIsActive }

    /// A game started through the default bottle's Steam is starting, running, or stopping.
    private var steamGameIsActive: Bool {
        activities.contains { id, activity in id > 0 && activity != .installing }
    }

    /// Once the game that kept Steam busy has ended, restart Steam so it reads the queued downloads.
    private func resumeWaitingInstalls() {
        guard !steamGameIsActive, installNotes.values.contains(.waitsForGame) else { return }
        for (id, note) in installNotes where note == .waitsForGame { installNotes[id] = nil }
        Task {
            try? await Task.detached { try Self.restartSteamSilently() }.value
            refreshSteamState()
        }
    }

    /// Opens Windows Steam's own window, for everything Archway doesn't cover.
    func openSteam() {
        Task {
            do {
                try await Task.detached { try Self.openSteamWindow() }.value
                refreshSteamState()
            } catch {
                NSSound.beep()
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
        isSteamRunning && !activities.keys.contains { $0 > 0 }
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
        guard let paths = try? AppPaths.app() else { return nil }
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
        if activities.values.contains(.installing) {
            store.refreshInstalled()
            resumeWaitingInstalls()
        }
        for (id, activity) in activities {
            if activity == .installing {
                if store.games.first(where: { $0.id == id })?.isInstalled == true {
                    finish(id)
                    scheduleSteamShutdown()
                } else {
                    let (phase, progress) = await Task.detached(operation: { Self.installState(appID: id) }).value
                    installPhases[id] = phase
                    // Steam moves the finished download out of its folder, so never step back.
                    if let progress { installProgress[id] = max(progress, installProgress[id] ?? 0) }
                    if phase != nil, installNotes[id] == .signIn { installNotes[id] = nil }
                }
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
                    if let game = store.games.first(where: { $0.id == id }), let context = launchContexts[id] {
                        let session = CompletedGameSession(game: game, context: context)
                        lastObservedSessions[id] = session
                        let promptKey = "compatibilityPrompted:\(id):\(context.runtimeVersion):\(context.graphicsBackend):\(context.profile.launchArguments.joined(separator: "|")): \(context.profile.graphicsAPI.rawValue)"
                        if !game.isLocal, activity != .stopping, !manuallyStopped.contains(id), completedSession == nil,
                           !UserDefaults.standard.bool(forKey: "disableCompatibilityFeedback"),
                           !UserDefaults.standard.bool(forKey: promptKey) {
                            completedSession = session
                            UserDefaults.standard.set(true, forKey: promptKey)
                        }
                    }
                    finish(id)
                    if id > 0 { scheduleSteamShutdown() }
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
        installProgress[id] = nil
        installPhases[id] = nil
        installNotes[id] = nil
        pendingFocus.remove(id)
        missedPolls[id] = nil
        startedAt[id] = nil
        manuallyStopped.remove(id)
        launchContexts[id] = nil
    }

    func dismissCompletedSession() { completedSession = nil }

    func showFeedback(for gameID: Int) {
        guard completedSession == nil else { return }
        completedSession = lastObservedSessions[gameID]
    }

    /// Shows the feedback sheet for a game without playing it, for design screenshots.
    func previewFeedback(for game: LibraryGame) {
        completedSession = CompletedGameSession(game: game, context: compatibility.context(for: game.id))
    }

    private func fail(_ game: LibraryGame, _ error: Error) {
        finish(game.id)
        errors[game.id] = Self.message(for: error)
    }

    // MARK: Work off the main thread

    nonisolated private static func orchestrator() throws -> Orchestrator {
        let paths = try AppPaths.app()
        guard let configuration = try ConfigStore(paths: paths).load() else { throw ArchwayError.missingConfiguration }
        return Orchestrator(paths: paths, configuration: configuration)
    }

    /// Matches the label of the request that starts the game.
    nonisolated private static func logLabel(for game: LibraryGame) -> String {
        game.isLocal ? "local-game-\(-game.id)" : "game-launch-\(game.id)"
    }

    /// Starts the game and returns the image names that identify its processes.
    nonisolated private static func launch(_ game: LibraryGame, profile: GameRuntimeProfile) throws -> Set<String> {
        let arguments = try profile.arguments(for: game.id)
        if let path = game.executablePath {
            let executable = URL(fileURLWithPath: path)
            try ProcessRunner.startGUIProcess(orchestrator().localGameLaunch(executable: executable, label: logLabel(for: game),
                                                                            gameArguments: arguments))
            return [executable.lastPathComponent.lowercased()]
        }
        let orchestrator = try orchestrator()
        let folder = orchestrator.steamInstallDirectory(appID: game.id)
        if game.id == Orchestrator.firstAppID { try orchestrator.prepareD3DMetalGame() }
        let shimActive = try orchestrator.prepareSteam()
        try ProcessRunner.sendGUIRequest(orchestrator.gameLaunch(appID: UInt32(game.id), webHelperShim: shimActive,
                                                                 silent: true, gameArguments: arguments))
        return folder.map(GameProcesses.executableNames) ?? []
    }

    /// Asks the game to close, then ends it if it is still there after a few seconds.
    nonisolated private static func stop(imageNames: Set<String>) throws {
        let orchestrator = try orchestrator()
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

    /// Asks Steam to exit and waits for the bottle's wineserver, like `archway close-steam`.
    nonisolated private static func closeSteam() throws {
        guard steamIsRunning() else { return }
        let orchestrator = try orchestrator()
        try ProcessRunner.sendGUIRequest(orchestrator.steamShutdown())
        try ProcessRunner.runSetup(orchestrator.wineserverWait(), timeout: 30)
    }

    /// Writes the game's manifest and starts Steam silently, restarting it first if asked. Returns whether Steam
    /// has a remembered sign-in; without one, Steam shows its login window and downloads afterwards.
    nonisolated private static func queueInstall(appID: Int, name: String, restartSteam: Bool) throws -> Bool {
        let orchestrator = try orchestrator()
        try orchestrator.queueSteamInstall(appID: appID, name: name)
        if restartSteam || !steamIsRunning() { try restartSteamSilently() }
        return orchestrator.steamIsSignedIn()
    }

    nonisolated private static func restartSteamSilently() throws {
        let orchestrator = try orchestrator()
        try closeSteam()
        let shimActive = try orchestrator.prepareSteam()
        try ProcessRunner.sendGUIRequest(orchestrator.steamOpen(webHelperShim: shimActive, silent: true))
    }

    nonisolated private static func installState(appID: Int) -> (Orchestrator.SteamInstallPhase?, Double?) {
        guard let orchestrator = try? orchestrator() else { return (nil, nil) }
        return (orchestrator.steamInstallPhase(appID: appID), orchestrator.steamInstallProgress(appID: appID))
    }

    nonisolated private static func openSteamWindow() throws {
        let orchestrator = try orchestrator()
        let shimActive = try orchestrator.prepareSteam()
        try ProcessRunner.sendGUIRequest(orchestrator.steamOpen(webHelperShim: shimActive))
    }

    nonisolated private static func message(for error: Error) -> String {
        switch error as? ArchwayError {
        case .missingConfiguration?: String(localized: "Archway isn’t set up on this Mac yet.")
        case .missingBottle?: String(localized: "Archway’s Windows environment isn’t set up yet.")
        case .missingSteam?: String(localized: "Windows Steam isn’t installed in Archway yet.")
        default: String(localized: "That didn’t work: \(error.localizedDescription)")
        }
    }
}
