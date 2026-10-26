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

    /// What Archway follows for one game, from starting or installing it until that ends.
    struct Session {
        var activity: Activity
        /// Local games run on their own; everything else goes through the default bottle's Steam.
        let usesSteam: Bool
        var startedAt = Date.now
        /// The image names that identify the game's processes, once it was launched.
        var imageNames: Set<String>?
        /// The game and its setup, for the question how it ran.
        var context: CompatibilityContext?
        /// The window comes to the front once it appears.
        var wantsFocus = false
        var stoppedByUser = false
        var missedPolls = 0
        /// Download progress from 0 to 1, once Steam has sized the download.
        var installProgress: Double?
        /// What Steam is doing for the install, once it has picked the game up.
        var installPhase: Orchestrator.SteamInstallPhase?
        var installNote: InstallNote?
    }

    private(set) var sessions: [Int: Session] = [:]
    /// Windows Steam runs in the default bottle.
    private(set) var isSteamRunning = false
    /// Stays after the session ends, until the next attempt.
    private(set) var errors: [Int: String] = [:]
    private(set) var uninstalling: Set<Int> = []
    private(set) var completedSession: CompletedGameSession?
    private(set) var lastObservedSessions: [Int: CompletedGameSession] = [:]

    struct CompletedGameSession: Identifiable {
        let id = UUID()
        let game: LibraryGame
        let context: CompatibilityContext
    }

    /// Why an install waits for Windows Steam: for its sign-in, or for a running game to end before Steam restarts.
    enum InstallNote: Equatable {
        case signIn
        case waitsForGame
    }

    nonisolated private let paths: AppPaths
    private let store: LibraryStore
    private let compatibility: CompatibilityStore
    private var watcher: Task<Void, Never>?
    /// Archway started Steam, so it also closes it once the game is over.
    private var ownsSteam = false
    private var steamShutdown: Task<Void, Never>?

    /// Steam, a first start, and shader caches can take a while before the game window appears.
    private static let startTimeout: TimeInterval = 240

    /// Steam uploads playtime and cloud saves after a game exits; give it time before closing it.
    private static let steamShutdownDelay: Duration = .seconds(15)

    init(paths: AppPaths, store: LibraryStore, compatibility: CompatibilityStore) {
        self.paths = paths
        self.store = store
        self.compatibility = compatibility
        // Games could once pick a separate alpha runtime; there is only one now.
        UserDefaults.standard.removeObject(forKey: "gameRuntimes")
        Task { await refreshSteamState() }
        // Steam keeps running when Archway quits otherwise, and restarts its window when only that is closed.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if self.ownsSteam { try? self.requestSteamShutdown() } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await self.refreshSteamState() }
        }
    }

    func activity(for game: LibraryGame) -> Activity? { sessions[game.id]?.activity }
    func session(for game: LibraryGame) -> Session? { sessions[game.id] }

    // MARK: Actions

    func play(_ game: LibraryGame) {
        guard sessions[game.id] == nil else { return }
        errors[game.id] = nil
        let profile = compatibility.profile(for: game.id)
        let usesSteam = !game.isLocal
        sessions[game.id] = Session(activity: .starting, usesSteam: usesSteam,
                                    context: compatibility.context(for: game.id, profile: profile), wantsFocus: true)
        if usesSteam { steamShutdown?.cancel() }
        Task {
            do {
                if usesSteam, await !Task.detached(operation: { self.steamIsRunning() }).value { ownsSteam = true }
                sessions[game.id]?.imageNames = try await Task.detached { try self.launch(game, profile: profile) }.value
                watch()
            } catch {
                fail(game, error)
            }
        }
    }

    func stop(_ game: LibraryGame) {
        guard case .running = sessions[game.id]?.activity, let names = sessions[game.id]?.imageNames else { return }
        sessions[game.id]?.activity = .stopping
        sessions[game.id]?.stoppedByUser = true
        Task {
            do {
                try await Task.detached { try self.stop(imageNames: names) }.value
            } catch {
                fail(game, error)
            }
        }
    }

    /// Queues the game for Steam and lets Steam download it in the background, without its window.
    /// Steam reads new downloads when it starts, so a running Steam restarts, unless a game needs it.
    func install(_ game: LibraryGame) {
        guard !game.isLocal, sessions[game.id] == nil else { return }
        errors[game.id] = nil
        sessions[game.id] = Session(activity: .installing, usesSteam: true)
        steamShutdown?.cancel()
        let gameNeedsSteam = steamGameIsActive
        Task {
            do {
                let wasRunning = await Task.detached(operation: { self.steamIsRunning() }).value
                if !wasRunning { ownsSteam = true }
                let signedIn = try await Task.detached {
                    try self.queueInstall(appID: game.id, name: game.title, restartSteam: wasRunning && !gameNeedsSteam)
                }.value
                if !signedIn { sessions[game.id]?.installNote = .signIn }
                if wasRunning && gameNeedsSteam { sessions[game.id]?.installNote = .waitsForGame }
                watch()
            } catch {
                fail(game, error)
            }
        }
    }

    /// Removes the game from the bottle. Steam closes first, so it doesn't restore what is being deleted.
    func uninstall(_ game: LibraryGame) {
        guard !game.isLocal, sessions[game.id] == nil, !uninstalling.contains(game.id), !steamGameIsActive else { return }
        errors[game.id] = nil
        uninstalling.insert(game.id)
        steamShutdown?.cancel()
        Task {
            do {
                try await Task.detached {
                    try self.closeSteam()
                    try self.orchestrator().uninstallSteamGame(appID: game.id)
                }.value
                ownsSteam = false
            } catch {
                errors[game.id] = Self.message(for: error)
            }
            uninstalling.remove(game.id)
            await refreshSteamState()
            await store.refreshInstalled()
        }
    }

    /// Uninstalling closes Steam, which would end a game that runs through it.
    var canUninstall: Bool { !steamGameIsActive }

    /// A game started through the default bottle's Steam is starting, running, or stopping.
    private var steamGameIsActive: Bool {
        sessions.values.contains { $0.usesSteam && $0.activity != .installing }
    }

    /// Once the game that kept Steam busy has ended, restart Steam so it reads the queued downloads.
    private func resumeWaitingInstalls() {
        let waiting = sessions.filter { $0.value.installNote == .waitsForGame }.keys
        guard !steamGameIsActive, !waiting.isEmpty else { return }
        for id in waiting { sessions[id]?.installNote = nil }
        Task {
            try? await Task.detached { try self.restartSteamSilently() }.value
            await refreshSteamState()
        }
    }

    /// Opens Windows Steam's own window, for everything Archway doesn't cover.
    func openSteam() {
        Task {
            do {
                try await Task.detached { try self.openSteamWindow() }.value
                await refreshSteamState()
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
        isSteamRunning && !sessions.values.contains(where: \.usesSteam)
    }

    private func shutDownSteam() async {
        ownsSteam = false
        try? await Task.detached { try self.closeSteam() }.value
        await refreshSteamState()
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

    private func refreshSteamState() async {
        isSteamRunning = await Task.detached { self.steamIsRunning() }.value
    }

    func showFolder(_ game: LibraryGame) {
        if let path = game.executablePath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if let folder = try? self.orchestrator().steamInstallDirectory(appID: game.id) {
            NSWorkspace.shared.open(folder)
        }
    }

    /// The log of the game's last start, if there is one.
    func logURL(for game: LibraryGame) -> URL? {
        let url = paths.logs.appendingPathComponent("\(Self.logLabel(for: game)).log")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Watching

    /// Polls the process list while anything is starting, running, stopping, or installing.
    private func watch() {
        guard watcher == nil else { return }
        watcher = Task {
            while !sessions.isEmpty, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await poll()
            }
            watcher = nil
        }
    }

    private func poll() async {
        await refreshSteamState()
        if sessions.values.contains(where: { $0.activity == .installing }) {
            await store.refreshInstalled()
            resumeWaitingInstalls()
        }
        for (id, session) in sessions {
            if session.activity == .installing {
                await pollInstall(id)
            } else {
                await pollGame(id, session)
            }
        }
    }

    private func pollInstall(_ id: Int) async {
        if store.games.first(where: { $0.id == id })?.isInstalled == true {
            finish(id)
            scheduleSteamShutdown()
            return
        }
        let (phase, progress) = await Task.detached(operation: { self.installState(appID: id) }).value
        guard var session = sessions[id] else { return }
        session.installPhase = phase
        // Steam moves the finished download out of its folder, so never step back.
        if let progress { session.installProgress = max(progress, session.installProgress ?? 0) }
        if phase != nil, session.installNote == .signIn { session.installNote = nil }
        sessions[id] = session
    }

    private func pollGame(_ id: Int, _ session: Session) async {
        guard let names = session.imageNames else { return }
        let processes = await Task.detached { GameProcesses.running(imageNames: names) }.value
        guard var session = sessions[id] else { return }
        let isRunning = !processes.isEmpty
        if isRunning, session.wantsFocus { session.wantsFocus = !bringToFront(processes) }
        switch session.activity {
        case .starting where isRunning:
            session.activity = .running(since: .now)
            session.startedAt = .now
        case .starting:
            if Date().timeIntervalSince(session.startedAt) > Self.startTimeout {
                finish(id)
                errors[id] = String(localized: "The game didn’t start. You’ll find the log under “Advanced”.")
                return
            }
        case .running, .stopping:
            // A game can restart itself (launchers, updates); only treat two misses in a row as an exit.
            session.missedPolls = isRunning ? 0 : session.missedPolls + 1
            if session.missedPolls >= 2 {
                ended(id, session)
                return
            }
        case .installing:
            break
        }
        sessions[id] = session
    }

    /// Records the playtime and, once per setup, asks how the game ran, unless the player stopped it.
    private func ended(_ id: Int, _ session: Session) {
        store.recordSession(gameID: id, from: session.startedAt, to: .now)
        if let game = store.games.first(where: { $0.id == id }), let context = session.context {
            let completed = CompletedGameSession(game: game, context: context)
            lastObservedSessions[id] = completed
            // The stray ": " stays; changing the key would ask again for every setup already answered.
            let promptKey = "compatibilityPrompted:\(id):\(context.runtimeVersion):\(context.graphicsBackend):\(context.profile.launchArguments.joined(separator: "|")): \(context.profile.graphicsAPI.rawValue)"
            if session.usesSteam, session.activity != .stopping, !session.stoppedByUser, completedSession == nil,
               !UserDefaults.standard.bool(forKey: "disableCompatibilityFeedback"),
               !UserDefaults.standard.bool(forKey: promptKey) {
                completedSession = completed
                UserDefaults.standard.set(true, forKey: promptKey)
            }
        }
        finish(id)
        if session.usesSteam { scheduleSteamShutdown() }
    }

    /// Activates the game once its window exists. Only while Archway is in front, so a game that takes
    /// long to start never pulls the player out of another app. Returns whether it is done trying.
    private func bringToFront(_ processes: [GameProcesses.Running]) -> Bool {
        guard NSApp.isActive else { return true }
        let apps = processes.compactMap { NSRunningApplication(processIdentifier: $0.pid) }
        guard let app = apps.first(where: { $0.activationPolicy == .regular }) else { return false }
        NSApp.yieldActivation(to: app)
        return app.activate()
    }

    private func finish(_ id: Int) { sessions[id] = nil }

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

    /// Reads the configuration each time, since setup and settings can change it while Archway runs.
    nonisolated private func orchestrator() throws -> Orchestrator {
        guard let configuration = try ConfigStore(paths: paths).load() else { throw ArchwayError.missingConfiguration }
        return Orchestrator(paths: paths, configuration: configuration)
    }

    /// Matches the label of the request that starts the game.
    nonisolated private static func logLabel(for game: LibraryGame) -> String {
        game.isLocal ? "local-game-\(-game.id)" : "game-launch-\(game.id)"
    }

    /// Starts the game and returns the image names that identify its processes.
    nonisolated private func launch(_ game: LibraryGame, profile: GameRuntimeProfile) throws -> Set<String> {
        let arguments = try profile.arguments(for: game.id)
        if let path = game.executablePath {
            let executable = URL(fileURLWithPath: path)
            try ProcessRunner.startGUIProcess(orchestrator().localGameLaunch(executable: executable, label: Self.logLabel(for: game),
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
    nonisolated private func stop(imageNames: Set<String>) throws {
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

    nonisolated private func steamIsRunning() -> Bool {
        (try? orchestrator().wineserverIsRunning()) == true
    }

    nonisolated private func requestSteamShutdown() throws {
        try ProcessRunner.sendGUIRequest(orchestrator().steamShutdown())
    }

    /// Asks Steam to exit and waits for the bottle's wineserver, like `archway close-steam`.
    nonisolated private func closeSteam() throws {
        guard steamIsRunning() else { return }
        let orchestrator = try orchestrator()
        try ProcessRunner.sendGUIRequest(orchestrator.steamShutdown())
        try ProcessRunner.runSetup(orchestrator.wineserverWait(), timeout: 30)
    }

    /// Writes the game's manifest and starts Steam silently, restarting it first if asked. Returns whether Steam
    /// has a remembered sign-in; without one, Steam shows its login window and downloads afterwards.
    nonisolated private func queueInstall(appID: Int, name: String, restartSteam: Bool) throws -> Bool {
        let orchestrator = try orchestrator()
        try orchestrator.queueSteamInstall(appID: appID, name: name)
        if restartSteam || !steamIsRunning() { try restartSteamSilently() }
        return orchestrator.steamIsSignedIn()
    }

    nonisolated private func restartSteamSilently() throws {
        let orchestrator = try orchestrator()
        try closeSteam()
        let shimActive = try orchestrator.prepareSteam()
        try ProcessRunner.sendGUIRequest(orchestrator.steamOpen(webHelperShim: shimActive, silent: true))
    }

    nonisolated private func installState(appID: Int) -> (Orchestrator.SteamInstallPhase?, Double?) {
        guard let orchestrator = try? orchestrator() else { return (nil, nil) }
        return (orchestrator.steamInstallPhase(appID: appID), orchestrator.steamInstallProgress(appID: appID))
    }

    nonisolated private func openSteamWindow() throws {
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
