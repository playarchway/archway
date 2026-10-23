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

    private(set) var activities: [Int: Activity] = [:]
    private(set) var errors: [Int: String] = [:]

    private let store: LibraryStore
    private var imageNames: [Int: Set<String>] = [:]
    private var startedAt: [Int: Date] = [:]
    private var missedPolls: [Int: Int] = [:]
    /// Games whose window should come to the front once it appears.
    private var pendingFocus: Set<Int> = []
    private var watcher: Task<Void, Never>?

    /// Steam, a first start, and shader caches can take a while before the game window appears.
    private static let startTimeout: TimeInterval = 240

    init(store: LibraryStore) {
        self.store = store
    }

    func activity(for game: LibraryGame) -> Activity? { activities[game.id] }

    // MARK: Actions

    func play(_ game: LibraryGame) {
        guard activities[game.id] == nil else { return }
        errors[game.id] = nil
        activities[game.id] = .starting
        startedAt[game.id] = .now
        pendingFocus.insert(game.id)
        Task {
            do {
                imageNames[game.id] = try await Task.detached { try Self.launch(game) }.value
                watch()
            } catch {
                fail(game, error)
            }
        }
    }

    func stop(_ game: LibraryGame) {
        guard case .running = activities[game.id], let names = imageNames[game.id] else { return }
        activities[game.id] = .stopping
        Task {
            do {
                try await Task.detached { try Self.stop(imageNames: names) }.value
            } catch {
                fail(game, error)
            }
        }
    }

    func install(_ game: LibraryGame) {
        guard !game.isLocal, activities[game.id] == nil else { return }
        errors[game.id] = nil
        activities[game.id] = .installing
        Task {
            do {
                try await Task.detached { try Self.install(appID: game.id) }.value
                watch()
            } catch {
                fail(game, error)
            }
        }
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
        guard let paths = try? AppPaths() else { return nil }
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
            case .starting:
                if Date().timeIntervalSince(startedAt[id] ?? .now) > Self.startTimeout {
                    finish(id)
                    errors[id] = "Das Spiel ist nicht gestartet. Unter „Erweitert“ findest du das Protokoll."
                }
            case .running, .stopping:
                // A game can restart itself (launchers, updates); only treat two misses in a row as an exit.
                missedPolls[id] = isRunning ? 0 : (missedPolls[id] ?? 0) + 1
                if (missedPolls[id] ?? 0) >= 2 { finish(id) }
            case .installing:
                break
            }
        }
    }

    /// Activates the game once its window exists. Only while Overcross is in front, so a game that takes
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
        missedPolls[id] = nil
        startedAt[id] = nil
    }

    private func fail(_ game: LibraryGame, _ error: Error) {
        finish(game.id)
        errors[game.id] = Self.message(for: error)
    }

    // MARK: Work off the main thread

    nonisolated private static func orchestrator() throws -> Orchestrator {
        let paths = try AppPaths()
        guard let configuration = try ConfigStore(paths: paths).load() else { throw OvercrossError.missingConfiguration }
        return Orchestrator(paths: paths, configuration: configuration)
    }

    nonisolated private static func logLabel(for game: LibraryGame) -> String {
        game.isLocal ? "local-game-\(-game.id)" : "game-launch-\(game.id)"
    }

    /// Starts the game and returns the image names that identify its processes.
    nonisolated private static func launch(_ game: LibraryGame) throws -> Set<String> {
        let orchestrator = try orchestrator()
        if let path = game.executablePath {
            let executable = URL(fileURLWithPath: path)
            try ProcessRunner.startGUIProcess(orchestrator.localGameLaunch(executable: executable, label: logLabel(for: game)))
            return [executable.lastPathComponent.lowercased()]
        }
        if game.id == Orchestrator.firstAppID { try orchestrator.prepareD3DMetalGame() }
        let shimActive = try orchestrator.prepareSteam()
        try ProcessRunner.sendGUIRequest(orchestrator.gameLaunch(appID: UInt32(game.id), webHelperShim: shimActive))
        guard let folder = orchestrator.steamInstallDirectory(appID: game.id) else { return [] }
        return GameProcesses.executableNames(in: folder)
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

    nonisolated private static func install(appID: Int) throws {
        let orchestrator = try orchestrator()
        let shimActive = try orchestrator.prepareSteam()
        try ProcessRunner.sendGUIRequest(orchestrator.gameInstall(appID: UInt32(appID), webHelperShim: shimActive))
    }

    nonisolated private static func message(for error: Error) -> String {
        switch error as? OvercrossError {
        case .missingConfiguration?: "Overcross ist auf diesem Mac noch nicht eingerichtet."
        case .missingBottle?: "Die Windows-Umgebung von Overcross ist noch nicht eingerichtet."
        case .missingSteam?: "Windows-Steam ist in Overcross noch nicht installiert."
        default: "Das hat nicht geklappt: \(error.localizedDescription)"
        }
    }
}
