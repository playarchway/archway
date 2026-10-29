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
        /// The Microsoft runtime being installed before the game starts.
        var installingRuntime: String?
        /// The logs as they were at the start, to read what the game wrote if it fails.
        var logs: LogSnapshot?
    }

    /// Whether Archway installs the Microsoft runtimes a game needs before starting it, or asks first.
    enum RuntimeInstallMode: String, CaseIterable {
        case automatic, ask
        static let defaultsKey = "runtimeInstallMode"
        static var current: RuntimeInstallMode {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(RuntimeInstallMode.init) ?? .automatic
        }
    }

    /// The question before a game starts, in the ask mode.
    struct RuntimePrompt: Identifiable {
        enum Answer { case install, startWithout, cancel }
        let id = UUID()
        let game: LibraryGame
        let runtimes: [WindowsRuntime]
        fileprivate let answer: CheckedContinuation<Answer, Never>
    }

    private(set) var runtimePrompt: RuntimePrompt?

    func answerRuntimePrompt(_ answer: RuntimePrompt.Answer) {
        guard let prompt = runtimePrompt else { return }
        runtimePrompt = nil
        prompt.answer.resume(returning: answer)
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
        Task { await refreshSteamState() }
        // A session that ended badly, for example while Archway wasn't running, may have left processes behind.
        Task.detached { [weak self] in _ = try? self?.orchestrator().endLeftoverProcesses() }
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
        let logs = paths.logs
        Task {
            do {
                guard await prepareRuntimes(for: game) else { return finish(game.id) }
                sessions[game.id]?.logs = await Task.detached { LogSnapshot(directory: logs) }.value
                if usesSteam, await !Task.detached(operation: { self.steamIsRunning() }).value { ownsSteam = true }
                sessions[game.id]?.imageNames = try await Task.detached { try self.launch(game, profile: profile) }.value
                watch()
            } catch {
                fail(game, error)
            }
        }
    }

    /// Installs the Microsoft runtimes the game needs and the bottle lacks, asking first in the ask mode. Returns
    /// false when the player cancels. A failed install doesn't stop the game: it may run on Wine's own DLLs.
    private func prepareRuntimes(for game: LibraryGame) async -> Bool {
        let learned = Self.learnedRuntimes(for: game.id)
        let missing = await Task.detached {
            guard let orchestrator = try? self.orchestrator() else { return [WindowsRuntime]() }
            let installed = orchestrator.installedRuntimes()
            let found = orchestrator.missingRuntimes(appID: game.isLocal ? nil : game.id,
                                                     executable: game.executablePath.map(URL.init(fileURLWithPath:)))
            return found + learned.filter { runtime in !installed.contains(runtime.id) && !found.contains(runtime) }
        }.value
        guard !missing.isEmpty else { return true }
        if RuntimeInstallMode.current == .ask {
            let answer = await withCheckedContinuation { runtimePrompt = RuntimePrompt(game: game, runtimes: missing, answer: $0) }
            switch answer {
            case .install: break
            case .startWithout: return true
            case .cancel: return false
            }
        }
        for runtime in missing {
            sessions[game.id]?.installingRuntime = runtime.name
            do {
                try await Task.detached { try await self.orchestrator().install(runtime) }.value
            } catch {
                errors[game.id] = String(localized: "\(runtime.name) couldn’t be installed. The game starts without it.")
            }
        }
        sessions[game.id]?.installingRuntime = nil
        return true
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
        InstallNotification.requestPermission()
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
        if let game = store.games.first(where: { $0.id == id }), game.isInstalled {
            InstallNotification.post(gameID: id, title: game.title)
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
                errors[id] = await explanation(for: id, session)
                    ?? String(localized: "The game didn’t start. You’ll find the log under “Advanced”.")
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

    // MARK: Diagnosis

    /// Runtimes a game turned out to need while running, which its programs' imports didn't show.
    private static func learnedRuntimes(for gameID: Int) -> [WindowsRuntime] {
        (UserDefaults.standard.stringArray(forKey: "learnedRuntimes:\(gameID)") ?? []).compactMap(WindowsRuntime.init(id:))
    }

    private static func learn(_ runtime: WindowsRuntime, for gameID: Int) {
        let key = "learnedRuntimes:\(gameID)"
        let ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? []).union([runtime.id])
        UserDefaults.standard.set(ids.sorted(), forKey: key)
    }

    /// Why the game failed, in words, if the logs since its start show a known reason.
    private func explanation(for id: Int, _ session: Session) async -> String? {
        guard let logs = session.logs else { return nil }
        let bottle = paths.bottle
        let (diagnosis, architecture) = await Task.detached { () -> (StartDiagnosis?, WindowsRuntime.Architecture?) in
            let diagnosis = StartDiagnosis.diagnose(logs.newText())
            guard case .missingDLL(_, let program)? = diagnosis,
                  let file = StartDiagnosis.file(forWindowsPath: program, bottle: bottle) else { return (diagnosis, nil) }
            return (diagnosis, WindowsRuntime.architecture(of: file))
        }.value
        switch diagnosis {
        case .missingDLL(let name, _)?:
            if let architecture, let runtime = WindowsRuntime.providing(dll: name, architecture: architecture) {
                Self.learn(runtime, for: id)
                return String(localized: "The game is missing \(name). Archway installs \(runtime.name) before the next start.")
            }
            return String(localized: "The game needs \(name), which Archway’s Windows environment doesn’t have.")
        case .antiCheat(let name)?:
            return String(localized: "The game uses \(name), which needs a Windows kernel driver and doesn’t run with Archway.")
        case .missingWineMono?:
            return String(localized: "The game needs .NET, but Wine Mono is missing from Archway’s Windows runtime.")
        case .steamUnavailable?:
            return String(localized: "The game couldn’t connect to Steam. Try starting it again.")
        case .crashed?:
            return String(localized: "The game crashed while starting. You’ll find the log under “Advanced”.")
        case nil:
            return nil
        }
    }

    /// Records the playtime and, once per setup, asks how the game ran, unless the player stopped it.
    private func ended(_ id: Int, _ session: Session) {
        // Closing within half a minute, unasked, is a failed start more often than a short session.
        if !session.stoppedByUser, Date().timeIntervalSince(session.startedAt) < 30 {
            Task { if let text = await explanation(for: id, session) { errors[id] = text } }
        }
        store.recordSession(gameID: id, from: session.startedAt, to: .now)
        if let game = store.games.first(where: { $0.id == id }), let context = session.context {
            let completed = CompletedGameSession(game: game, context: context)
            lastObservedSessions[id] = completed
            // The stray ": " stays; changing the key would ask again for every setup already answered.
            let promptKey = "compatibilityPrompted:\(id):\(context.runtimeVersion):\(context.graphicsBackend):\(context.profile.launchArguments.joined(separator: "|")): \(context.profile.graphicsAPI.rawValue)"
            if session.usesSteam, session.activity != .stopping, !session.stoppedByUser, completedSession == nil,
               CompatibilityStore.acceptsReports,
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
        try Orchestrator(paths: paths)
    }

    /// Matches the label of the request that starts the game.
    nonisolated private static func logLabel(for game: LibraryGame) -> String {
        game.isLocal ? "local-game-\(-game.id)" : "game-launch-\(game.id)"
    }

    /// Starts the game and returns the image names that identify its processes.
    nonisolated private func launch(_ game: LibraryGame, profile: GameRuntimeProfile) throws -> Set<String> {
        let arguments = try profile.arguments()
        if let path = game.executablePath {
            let executable = URL(fileURLWithPath: path)
            try ProcessRunner.startGUIProcess(orchestrator().localGameLaunch(executable: executable, label: Self.logLabel(for: game),
                                                                            gameArguments: arguments))
            return [executable.lastPathComponent.lowercased()]
        }
        let orchestrator = try orchestrator()
        let folder = orchestrator.steamInstallDirectory(appID: game.id)
        try orchestrator.prepareD3DMetalGame(appID: game.id)
        try ProcessRunner.sendGUIRequest(orchestrator.gameLaunch(appID: UInt32(game.id), silent: true,
                                                                 gameArguments: arguments))
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
        orchestrator.endLeftoverProcesses()
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
        try closeSteam()
        try ProcessRunner.sendGUIRequest(orchestrator().steamOpen(silent: true))
    }

    nonisolated private func installState(appID: Int) -> (Orchestrator.SteamInstallPhase?, Double?) {
        guard let orchestrator = try? orchestrator() else { return (nil, nil) }
        return (orchestrator.steamInstallPhase(appID: appID), orchestrator.steamInstallProgress(appID: appID))
    }

    nonisolated private func openSteamWindow() throws {
        try ProcessRunner.sendGUIRequest(orchestrator().steamOpen())
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
